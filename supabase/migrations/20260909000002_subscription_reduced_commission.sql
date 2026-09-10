-- ── reduced_commission_pct: apply subscription commission discount ─────────────
--
-- When a vendor holds an active global subscription plan with
-- reduced_commission_pct > 0, the wallet commission trigger applies a
-- proportional discount after the base commission is accumulated.
--
-- Calculation: finalCommission = baseCommission × (1 − reducedPct / 100)
--
-- The Dart settlement client applies the same reduction on the live path
-- (vendor_settlement_repository.dart) so settlement snapshots and wallet
-- deductions remain in sync.
--
-- Both native-service and custom-service booking items are covered because
-- the reduction is applied to the total v_commission after the item loop,
-- not per-item.  The base commission resolution (resolve_catalog_module_config
-- + commission_rules fallback) is unchanged.

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

  -- Idempotency: commission already deducted for this booking.
  IF EXISTS (
    SELECT 1 FROM wallet_transactions
     WHERE reference_id   = NEW.id
       AND reference_type = 'booking'
       AND type           = 'commission'
  ) THEN
    RETURN NEW;
  END IF;

  -- Fallback rule: vendor-specific > global.
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

  -- Subscription commission discount (global sub only).
  -- Prefer snapshot permissions so admin plan edits don't affect active subs.
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
  -- Resolution: catalog-scoped config → fallback rule (vendor > global).
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

  WITH deduction AS (
    UPDATE vendor_wallets
       SET available_balance = available_balance - v_commission,
           updated_at        = now()
     WHERE vendor_id = NEW.vendor_id
    RETURNING available_balance
  )
  INSERT INTO wallet_transactions (
    vendor_id, type, amount, balance_after,
    reference_id, reference_type, description
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
