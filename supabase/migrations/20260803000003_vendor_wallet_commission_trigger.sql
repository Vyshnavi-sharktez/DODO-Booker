-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 2: Automatic Commission Deduction on Booking Completion
--
-- Fires after a booking transitions to 'completed'.
-- Calculates commission per booking item using the same resolution order
-- as the Vendor Payout module (catalog-scoped config → commission_rules
-- vendor rule → commission_rules global rule), then deducts the total from
-- vendor_wallets.available_balance.
--
-- The existing trg_sync_wallet_balance trigger (Phase 1) propagates the new
-- available_balance to vendors.wallet_balance automatically.
--
-- Idempotent: a second status-to-completed update on the same booking is a
-- no-op because the wallet_transactions guard fires first.
--
-- Vendor Payout module is not touched — commission_rules is read-only here.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_deduct_commission_on_booking_complete()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_fallback_type  TEXT;
  v_fallback_value NUMERIC;
  v_item           RECORD;
  v_scoped_config  JSONB;
  v_item_commission NUMERIC;
  v_commission     NUMERIC(12,2) := 0;
  v_new_balance    NUMERIC;
BEGIN
  -- Skip if no vendor is assigned to this booking
  IF NEW.vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Idempotency guard: commission already deducted for this booking
  IF EXISTS (
    SELECT 1 FROM wallet_transactions
     WHERE reference_id   = NEW.id
       AND reference_type = 'booking'
       AND type           = 'commission'
  ) THEN
    RETURN NEW;
  END IF;

  -- Resolve fallback rule from commission_rules (vendor-specific > global).
  -- Matches the payout module's _resolveRule(vendorId, null, ...) call.
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

  -- Sum commission across all booking items.
  -- Resolution order per item: catalog-scoped config → fallback rule.
  -- Commission base is booking_items.total_price (pre-tax, pre-discount),
  -- matching the payout module convention.
  FOR v_item IN
    SELECT bi.service_id, bi.catalog_parent_node_id, bi.total_price
      FROM booking_items bi
     WHERE bi.booking_id = NEW.id
       AND bi.total_price > 0
  LOOP
    v_scoped_config := resolve_catalog_module_config(
      'commission',
      v_item.service_id,
      v_item.catalog_parent_node_id
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

  -- Round to 2 decimal places to match wallet_transactions.amount precision
  v_commission := ROUND(v_commission, 2);

  -- Nothing to deduct (zero-commission booking or no items)
  IF v_commission = 0 THEN
    RETURN NEW;
  END IF;

  -- Deduct from wallet and record the transaction in one atomic CTE statement.
  -- Both the UPDATE and INSERT succeed or fail together; neither can commit
  -- without the other. If vendor_wallets row is missing the CTE returns no
  -- rows and the INSERT is skipped — no transaction is recorded.
  -- trg_sync_wallet_balance propagates available_balance → vendors.wallet_balance.
  WITH deduction AS (
    UPDATE vendor_wallets
       SET available_balance = available_balance - v_commission,
           updated_at        = now()
     WHERE vendor_id = NEW.vendor_id
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
    NEW.vendor_id,
    'commission',
    v_commission,
    d.available_balance,
    NEW.id,
    'booking',
    'Commission deducted on booking completion'
  FROM deduction d;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_deduct_commission_on_completion
  AFTER UPDATE ON bookings
  FOR EACH ROW
  WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
  EXECUTE FUNCTION fn_deduct_commission_on_booking_complete();
