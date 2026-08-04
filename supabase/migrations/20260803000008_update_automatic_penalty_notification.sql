-- ─────────────────────────────────────────────────────────────────────────────
-- Update fn_deduct_vendor_cancellation_penalty() to include dynamic reason & amount in vendor notification
-- ─────────────────────────────────────────────────────────────────────────────

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
  IF NEW.status = 'rejected' THEN
    v_event_type  := 'rejection';
    v_enabled_key := 'penalty_vendor_rejection_enabled';
    v_amount_key  := 'penalty_vendor_rejection_amount';
    v_description := 'Vendor Rejection Penalty';
  ELSIF NEW.status = 'cancelled' AND (
    NEW.cancelled_by = 'vendor' OR OLD.cancelled_by = 'vendor'
  ) THEN
    v_event_type  := 'cancellation';
    v_enabled_key := 'penalty_vendor_cancellation_enabled';
    v_amount_key  := 'penalty_vendor_cancellation_amount';
    v_description := 'Vendor Cancellation Penalty';
  ELSIF NEW.status = 'no_show' AND (
    NEW.cancelled_by = 'vendor' OR OLD.cancelled_by = 'vendor' OR NEW.vendor_id IS NOT NULL
  ) THEN
    v_event_type  := 'noshow';
    v_enabled_key := 'penalty_vendor_noshow_enabled';
    v_amount_key  := 'penalty_vendor_noshow_amount';
    v_description := 'Vendor No-Show Penalty';
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

  -- Send vendor notification for automated penalty with dynamic amount & reason
  INSERT INTO notifications (
    user_type, user_id, title, message, notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'vendor',
    v_target_vendor_id,
    'Wallet Penalty Charged',
    'A penalty of ₹' || TRIM(TO_CHAR(v_amount, '999999990.00')) || ' was charged to your wallet. Reason: ' || v_description || '.',
    'wallet_penalty',
    'vendor_wallet',
    NEW.id,
    false,
    now()
  );

  RETURN NEW;
END;
$$;
