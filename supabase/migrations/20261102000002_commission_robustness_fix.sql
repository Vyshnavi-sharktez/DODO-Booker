-- ── Commission robustness fix ─────────────────────────────────────────────────
--
-- Problems fixed:
--
--   1. Silent miss on missing vendor_wallets row.
--      The original CTE pattern (UPDATE … RETURNING … then INSERT … FROM cte)
--      inserts nothing when the UPDATE matches zero rows. A vendor created before
--      fn_on_vendor_created was deployed, or seeded directly, has no wallet row
--      and every completion silently skips commission deduction.
--
--      Fix: INSERT … ON CONFLICT DO NOTHING before the deduction UPDATE so the
--      row always exists.  Explicit UPDATE + INSERT replaces the CTE, guaranteeing
--      the INSERT always runs.
--
--   2. commission_reversal type not registered.
--      Refund/cancellation of a completed booking should credit the vendor's wallet
--      back with a distinct 'commission_reversal' type so the ledger is symmetric.
--      Without the type being in the CHECK constraint any INSERT would be rejected.
--
--   3. No commission reversal trigger.
--      When a completed booking transitions to 'cancelled' or 'refunded' the
--      original commission must be returned to the vendor wallet.
--
-- Out of scope (unchanged):
--   • Negative wallet balances remain allowed — the wallet is a pre-paid security
--     deposit and vendors top it up; going into debt is an admin concern.
--   • Commission rate resolution logic is unchanged (resolve_catalog_module_config
--     + subscription discount already correct in 20260909000002).
--   • Payment method is NOT filtered — all completed bookings are commission-eligible
--     regardless of whether payment was Razorpay, COD, UPI or any other method.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Register commission_reversal type ─────────────────────────────────────

ALTER TABLE wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check
    CHECK (type IN (
      'top_up',
      'commission',
      'commission_reversal',
      'penalty',
      'adjustment',
      'refund_adjustment'
    ));

-- ── 2. Robust commission deduction trigger ────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_deduct_commission_on_booking_complete()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_fallback_type   TEXT;
  v_fallback_value  NUMERIC;
  v_item            RECORD;
  v_scoped_config   JSONB;
  v_item_commission NUMERIC;
  v_commission      NUMERIC(12,2) := 0;
  v_reduced_pct     NUMERIC       := 0;
  v_new_balance     NUMERIC;
BEGIN
  IF NEW.vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Idempotency: any commission transaction already recorded for this booking.
  IF EXISTS (
    SELECT 1 FROM wallet_transactions
     WHERE reference_id   = NEW.id
       AND reference_type = 'booking'
       AND type           = 'commission'
  ) THEN
    RETURN NEW;
  END IF;

  -- Fallback commission rule: vendor-specific overrides global.
  SELECT cr.commission_type, cr.commission_value
    INTO v_fallback_type, v_fallback_value
    FROM commission_rules cr
   WHERE cr.is_enabled = true
     AND (
           (cr.rule_type = 'vendor' AND cr.target_id = NEW.vendor_id)
        OR (cr.rule_type = 'global' AND cr.target_id IS NULL)
     )
   ORDER BY CASE cr.rule_type WHEN 'vendor' THEN 1 ELSE 2 END
   LIMIT 1;

  -- Subscription commission discount (global subscription only).
  -- Prefer snapshot permissions so plan edits don't affect in-flight subs.
  SELECT COALESCE(
           (vs.subscription_permissions->>'reduced_commission_pct')::NUMERIC,
           (sp.permissions->>'reduced_commission_pct')::NUMERIC,
           0
         )
    INTO v_reduced_pct
    FROM vendor_subscriptions vs
    LEFT JOIN subscription_plans sp ON sp.id = vs.plan_id
   WHERE vs.vendor_id       = NEW.vendor_id
     AND vs.catalog_node_id IS NULL
     AND vs.status          = 'active'
     AND vs.expiry_date     > NOW()
   LIMIT 1;

  -- Accumulate commission per booking item.
  -- Resolution order: catalog-scoped config → vendor rule → global rule.
  FOR v_item IN
    SELECT bi.service_id,
           bi.catalog_parent_node_id,
           bi.total_price,
           bi.custom_service_id
      FROM booking_items bi
     WHERE bi.booking_id = NEW.id
       AND bi.total_price > 0
  LOOP
    v_scoped_config := resolve_catalog_module_config(
      'commission',
      v_item.service_id,
      v_item.catalog_parent_node_id,
      v_item.custom_service_id
    );

    IF v_scoped_config IS NOT NULL THEN
      IF (v_scoped_config->>'commission_type') = 'percentage' THEN
        v_item_commission :=
          v_item.total_price * (v_scoped_config->>'commission_value')::NUMERIC / 100;
      ELSE
        v_item_commission := (v_scoped_config->>'commission_value')::NUMERIC;
      END IF;
    ELSIF v_fallback_type IS NOT NULL THEN
      IF v_fallback_type = 'percentage' THEN
        v_item_commission := v_item.total_price * v_fallback_value / 100;
      ELSE
        v_item_commission := v_fallback_value;
      END IF;
    ELSE
      v_item_commission := 0;
    END IF;

    v_commission := v_commission + GREATEST(v_item_commission, 0);
  END LOOP;

  -- Apply subscription discount after all items are summed.
  IF v_reduced_pct > 0 AND v_reduced_pct < 100 THEN
    v_commission := v_commission * (1 - v_reduced_pct / 100.0);
  END IF;

  v_commission := ROUND(v_commission, 2);

  IF v_commission = 0 THEN
    RETURN NEW;
  END IF;

  -- Guarantee wallet row exists. fn_on_vendor_created normally creates it, but
  -- vendors seeded before that trigger was deployed may not have a row.
  INSERT INTO vendor_wallets (vendor_id, available_balance)
  VALUES (NEW.vendor_id, 0)
  ON CONFLICT (vendor_id) DO NOTHING;

  -- Deduct commission. Negative balance is allowed — vendor must top up.
  UPDATE vendor_wallets
     SET available_balance = available_balance - v_commission,
         updated_at        = now()
   WHERE vendor_id = NEW.vendor_id
  RETURNING available_balance INTO v_new_balance;

  -- Explicit INSERT (not CTE-chained) so it always runs even if UPDATE returns
  -- no rows due to a race condition.
  INSERT INTO wallet_transactions (
    vendor_id, type, amount, balance_after,
    reference_id, reference_type, description
  ) VALUES (
    NEW.vendor_id,
    'commission',
    v_commission,
    COALESCE(v_new_balance, -v_commission),
    NEW.id,
    'booking',
    'Commission deducted on booking completion'
  );

  RETURN NEW;
END;
$$;

-- ── 3. Commission reversal on refund / cancellation ───────────────────────────

CREATE OR REPLACE FUNCTION fn_reverse_commission_on_refund()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_commission  NUMERIC(12,2);
  v_new_balance NUMERIC;
BEGIN
  IF NEW.vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Idempotency: reversal already recorded for this booking.
  IF EXISTS (
    SELECT 1 FROM wallet_transactions
     WHERE reference_id   = NEW.id
       AND reference_type = 'booking'
       AND type           = 'commission_reversal'
  ) THEN
    RETURN NEW;
  END IF;

  -- Find the original commission amount to reverse.
  SELECT amount INTO v_commission
    FROM wallet_transactions
   WHERE reference_id   = NEW.id
     AND reference_type = 'booking'
     AND type           = 'commission'
   LIMIT 1;

  IF v_commission IS NULL OR v_commission = 0 THEN
    RETURN NEW;
  END IF;

  -- Credit the commission back to the vendor wallet.
  UPDATE vendor_wallets
     SET available_balance = available_balance + v_commission,
         updated_at        = now()
   WHERE vendor_id = NEW.vendor_id
  RETURNING available_balance INTO v_new_balance;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  INSERT INTO wallet_transactions (
    vendor_id, type, amount, balance_after,
    reference_id, reference_type, description
  ) VALUES (
    NEW.vendor_id,
    'commission_reversal',
    v_commission,
    v_new_balance,
    NEW.id,
    'booking',
    'Commission reversed on booking refund/cancellation'
  );

  RETURN NEW;
END;
$$;

-- Fires when a completed booking transitions to cancelled or refunded.
DROP TRIGGER IF EXISTS trg_reverse_commission_on_refund ON bookings;

CREATE TRIGGER trg_reverse_commission_on_refund
  AFTER UPDATE ON bookings
  FOR EACH ROW
  WHEN (
    OLD.status = 'completed'
    AND NEW.status IN ('cancelled', 'refunded')
    AND NEW.vendor_id IS NOT NULL
  )
  EXECUTE FUNCTION fn_reverse_commission_on_refund();
