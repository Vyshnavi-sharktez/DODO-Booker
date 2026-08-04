-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 4: Vendor Cancellation Penalties
--
-- 1. Global settings seed for event-scoped penalty rules:
--    - Vendor Rejection:    penalty_vendor_rejection_enabled, penalty_vendor_rejection_amount
--    - Vendor Cancellation: penalty_vendor_cancellation_enabled, penalty_vendor_cancellation_amount
--    - Vendor No-Show:      penalty_vendor_noshow_enabled, penalty_vendor_noshow_amount
--
-- 2. Trigger function fn_deduct_vendor_cancellation_penalty()
--    Fires after a booking transitions to 'rejected', 'cancelled', or 'no_show'.
--    Strictly applies penalties ONLY for vendor-triggered events. Customer & Admin
--    cancellations are explicitly excluded.
--    Atomic & Idempotent.
--
-- 3. Admin Manual Penalty RPC: admin_apply_manual_penalty()
--    Allows admins to issue custom penalties with a mandatory reason.
--    Deducts amount from vendor_wallets, creates a 'penalty' ledger entry with
--    reference_type = 'manual', and sends a notification to the vendor.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Global Settings Seed ──────────────────────────────────────────────────

INSERT INTO settings (setting_key, setting_value) VALUES
  ('penalty_vendor_rejection_enabled',    'false'),
  ('penalty_vendor_rejection_amount',     '0'),
  ('penalty_vendor_cancellation_enabled', 'false'),
  ('penalty_vendor_cancellation_amount',  '0'),
  ('penalty_vendor_noshow_enabled',       'false'),
  ('penalty_vendor_noshow_amount',        '0')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 2. Automatic Vendor Cancellation Penalty Trigger ──────────────────────────

CREATE OR REPLACE FUNCTION fn_deduct_vendor_cancellation_penalty()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_target_vendor_id  UUID;
  v_event_type        TEXT;
  v_enabled_key       TEXT;
  v_amount_key        TEXT;
  v_enabled_setting   TEXT;
  v_amount_setting    TEXT;
  v_is_enabled        BOOLEAN := false;
  v_amount            NUMERIC := 0;
  v_description       TEXT;
BEGIN
  -- Target vendor resolution
  v_target_vendor_id := COALESCE(NEW.vendor_id, OLD.vendor_id);
  IF v_target_vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Strictly filter vendor-triggered events only:
  --  a) status = 'rejected' -> Vendor rejected an assigned booking
  --  b) status = 'cancelled' AND cancelled_by = 'vendor' -> Vendor cancelled accepted booking
  --  c) status = 'no_show' AND (cancelled_by = 'vendor' OR NEW.vendor_id IS NOT NULL) -> Vendor no-show
  IF NEW.status = 'rejected' THEN
    v_event_type  := 'rejection';
    v_enabled_key := 'penalty_vendor_rejection_enabled';
    v_amount_key  := 'penalty_vendor_rejection_amount';
    v_description := 'Vendor rejection penalty fee';
  ELSIF NEW.status = 'cancelled' AND (
    NEW.cancelled_by = 'vendor' OR OLD.cancelled_by = 'vendor'
  ) THEN
    v_event_type  := 'cancellation';
    v_enabled_key := 'penalty_vendor_cancellation_enabled';
    v_amount_key  := 'penalty_vendor_cancellation_amount';
    v_description := 'Vendor cancellation penalty fee';
  ELSIF NEW.status = 'no_show' AND (
    NEW.cancelled_by = 'vendor' OR OLD.cancelled_by = 'vendor' OR NEW.vendor_id IS NOT NULL
  ) THEN
    v_event_type  := 'noshow';
    v_enabled_key := 'penalty_vendor_noshow_enabled';
    v_amount_key  := 'penalty_vendor_noshow_amount';
    v_description := 'Vendor no-show penalty fee';
  ELSE
    -- Customer or Admin cancellations MUST NOT trigger a penalty
    RETURN NEW;
  END IF;

  -- Idempotency guard: penalty already deducted for this booking
  IF EXISTS (
    SELECT 1 FROM wallet_transactions
     WHERE reference_id   = NEW.id
       AND reference_type = 'booking'
       AND type           = 'penalty'
  ) THEN
    RETURN NEW;
  END IF;

  -- Read configured rule settings
  SELECT setting_value INTO v_enabled_setting
    FROM settings
   WHERE setting_key = v_enabled_key;

  SELECT setting_value INTO v_amount_setting
    FROM settings
   WHERE setting_key = v_amount_key;

  v_is_enabled := (LOWER(TRIM(COALESCE(v_enabled_setting, 'false'))) = 'true');
  v_amount := COALESCE(NULLIF(TRIM(v_amount_setting), '')::NUMERIC, 0);

  -- Penalty rule disabled or zero amount
  IF NOT v_is_enabled OR v_amount <= 0 THEN
    RETURN NEW;
  END IF;

  -- Deduct penalty amount from wallet and record ledger entry atomically
  WITH deduction AS (
    UPDATE vendor_wallets
       SET available_balance = available_balance - v_amount,
           updated_at        = now()
     WHERE vendor_id = v_target_vendor_id
    RETURNING available_balance
  )
  INSERT INTO wallet_transactions (
    vendor_id,
    type,
    amount,
    balance_after,
    reference_id,
    reference_type,
    description
  )
  SELECT
    v_target_vendor_id,
    'penalty',
    v_amount,
    d.available_balance,
    NEW.id,
    'booking',
    v_description
  FROM deduction d;

  -- Send vendor notification for automated penalty
  INSERT INTO notifications (
    user_type, user_id, title, message, notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'vendor',
    v_target_vendor_id,
    'Wallet Penalty Charged',
    'A penalty of ₹' || TRIM(TO_CHAR(v_amount, '999999990.00')) || ' was charged for booking cancellation/rejection.',
    'wallet_penalty',
    'vendor_wallet',
    NEW.id,
    false,
    now()
  );

  RETURN NEW;
END;
$$;

-- Attach trigger to bookings table
DROP TRIGGER IF EXISTS trg_deduct_vendor_cancellation_penalty ON bookings;

CREATE TRIGGER trg_deduct_vendor_cancellation_penalty
  AFTER UPDATE ON bookings
  FOR EACH ROW
  WHEN (NEW.status IN ('rejected', 'cancelled', 'no_show') AND OLD.status NOT IN ('rejected', 'cancelled', 'no_show'))
  EXECUTE FUNCTION fn_deduct_vendor_cancellation_penalty();

-- ── 3. Admin Manual Penalty RPC Function ─────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_apply_manual_penalty(
  p_vendor_id   UUID,
  p_amount      NUMERIC,
  p_reason      TEXT,
  p_admin_id    UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_new_balance    NUMERIC;
  v_transaction_id UUID;
  v_trimmed_reason TEXT;
BEGIN
  v_trimmed_reason := TRIM(COALESCE(p_reason, ''));

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Penalty amount must be positive';
  END IF;

  IF v_trimmed_reason = '' THEN
    RAISE EXCEPTION 'A valid reason is required for applying a manual penalty';
  END IF;

  UPDATE vendor_wallets
     SET available_balance = available_balance - p_amount,
         updated_at        = now()
   WHERE vendor_id = p_vendor_id
  RETURNING available_balance INTO v_new_balance;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Wallet not found for vendor %', p_vendor_id;
  END IF;

  INSERT INTO wallet_transactions (
    vendor_id, type, amount, balance_after,
    reference_type, description, created_by
  ) VALUES (
    p_vendor_id, 'penalty', p_amount, v_new_balance,
    'manual', v_trimmed_reason, p_admin_id
  )
  RETURNING id INTO v_transaction_id;

  -- Send vendor notification
  INSERT INTO notifications (
    user_type, user_id, title, message, notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'vendor',
    p_vendor_id,
    'Wallet Penalty Applied',
    'A penalty of ₹' || TRIM(TO_CHAR(p_amount, '999999990.00')) || ' was charged to your wallet. Reason: ' || v_trimmed_reason,
    'wallet_penalty',
    'vendor_wallet',
    v_transaction_id,
    false,
    now()
  );

  RETURN v_transaction_id;
END;
$$;
