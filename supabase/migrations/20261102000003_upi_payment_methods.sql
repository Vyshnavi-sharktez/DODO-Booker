-- ── UPI Payment Methods ────────────────────────────────────────────────────────
--
-- Adds two new payment method values:
--   upi_dodo   — Customer pays DODO's UPI/QR directly; DODO collects → settlement
--   upi_vendor — Customer pays vendor's UPI; vendor collects → wallet commission
--
-- Commission routing change:
--   Online payments (razorpay, upi_dodo) → DODO collects the gross.
--   Commission is retained by DODO at settlement time (gross − commission = net payout).
--   No wallet deduction is needed for these bookings.
--
--   Vendor-collected (cash, cod) → vendor holds the cash.
--   DODO's commission is deducted from the vendor's pre-paid security wallet.
--
-- Settlement guard:
--   Only online-payment bookings (razorpay, upi_dodo) are eligible for vendor
--   settlement.  Vendor-collected bookings are excluded — the vendor already has
--   the full amount and owes DODO commission (collected via wallet).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Add upi_reference column ───────────────────────────────────────────────
-- Stores the customer-provided UTR (transaction reference) for upi_dodo bookings.
-- Optional — customers are not required to submit UTR.

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS upi_reference TEXT;

-- ── 2. is_online_payment() helper ─────────────────────────────────────────────
-- Returns TRUE when DODO collected the payment (Razorpay or DODO UPI).
-- Used by triggers and RPCs to route commission vs. settlement.

CREATE OR REPLACE FUNCTION is_online_payment(p_method TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SECURITY DEFINER AS $$
  SELECT LOWER(COALESCE(p_method, '')) IN ('razorpay', 'online', 'upi_dodo')
$$;

-- ── 3. Commission trigger — skip wallet deduction for online payments ──────────
-- Replaces fn_deduct_commission_on_booking_complete from 20261102000002.
-- Identical except the first guard: returns early when DODO collected the payment.

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

  -- For online payments (razorpay, upi_dodo) DODO already holds the gross.
  -- Commission is retained during settlement — no wallet deduction needed.
  IF is_online_payment(NEW.payment_method) THEN
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

  -- Apply subscription discount.
  IF v_reduced_pct > 0 AND v_reduced_pct < 100 THEN
    v_commission := v_commission * (1 - v_reduced_pct / 100.0);
  END IF;

  v_commission := ROUND(v_commission, 2);

  IF v_commission = 0 THEN
    RETURN NEW;
  END IF;

  -- Guarantee wallet row exists.
  INSERT INTO vendor_wallets (vendor_id, available_balance)
  VALUES (NEW.vendor_id, 0)
  ON CONFLICT (vendor_id) DO NOTHING;

  UPDATE vendor_wallets
     SET available_balance = available_balance - v_commission,
         updated_at        = now()
   WHERE vendor_id = NEW.vendor_id
  RETURNING available_balance INTO v_new_balance;

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

-- ── 4. Update COD eligibility check ───────────────────────────────────────────
-- Vendor-collected methods: cash, cod only.

CREATE OR REPLACE FUNCTION fn_enforce_cod_vendor_eligibility()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  -- Vendor-collected methods: cash, cod.
  -- Any DODO-collected method (razorpay, upi_dodo, online) bypasses this check.
  IF NEW.vendor_id IS NULL
   OR LOWER(COALESCE(NEW.payment_method, '')) NOT IN ('cash', 'cod') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.vendor_id      IS NOT DISTINCT FROM NEW.vendor_id
     AND OLD.payment_method IS NOT DISTINCT FROM NEW.payment_method THEN
    RETURN NEW;
  END IF;

  IF NOT check_vendor_cod_eligibility(NEW.vendor_id) THEN
    RAISE EXCEPTION
      'Vendor % is not eligible to accept vendor-collected bookings. '
      'Verify that the vendor has an active subscription with COD permission.',
      NEW.vendor_id
    USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- ── 5. Update assignment guard to include upi_dodo ────────────────────────────
-- upi_dodo uses is_online_payment() which already covers razorpay + upi_dodo.
-- The guard blocks assignment when payment is unverified for online payments.
-- For upi_dodo we do NOT block dispatch (manual verification is async).

CREATE OR REPLACE FUNCTION fn_guard_razorpay_assignment()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Guard only applies to Razorpay; upi_dodo is verified manually and
  -- should not block dispatch.
  IF LOWER(COALESCE(NEW.payment_method, '')) NOT IN ('razorpay', 'online') THEN
    RETURN NEW;
  END IF;

  IF NEW.status IN ('assigned', 'assigned_to_dodo_team')
     AND OLD.status NOT IN (
       'assigned', 'assigned_to_dodo_team',
       'accepted', 'en_route', 'in_progress', 'started',
       'awaiting_verification', 'completed'
     )
     AND COALESCE(NEW.payment_status, '') <> 'success'
  THEN
    RAISE EXCEPTION
      'Cannot assign booking % — Razorpay payment has not been verified '
      '(payment_status = %). Verify payment or cancel the booking first.',
      NEW.id,
      COALESCE(NEW.payment_status, 'null')
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- ── 6. Settlement RPC — reject vendor-collected bookings ──────────────────────
-- Only razorpay and upi_dodo bookings are eligible for vendor settlement.
-- cash/cod/upi_vendor are vendor-collected; vendor keeps the full amount and
-- DODO collects commission via wallet deduction.

DROP FUNCTION IF EXISTS create_vendor_settlement_batch(UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION create_vendor_settlement_batch(
  p_vendor_id        UUID,
  p_vendor_name      TEXT,
  p_settled_by       UUID,
  p_payment_method   TEXT,
  p_reference_number TEXT,
  p_notes            TEXT,
  p_bookings         JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_settlement_id  UUID;
  v_total_amount   NUMERIC(12,2) := 0;
  v_booking        JSONB;
  v_booking_id     UUID;
  v_count          INT;
  v_pay_method     TEXT;
BEGIN
  IF p_bookings IS NULL OR jsonb_array_length(p_bookings) = 0 THEN
    RAISE EXCEPTION 'No bookings selected for settlement';
  END IF;

  FOR v_booking IN SELECT value FROM jsonb_array_elements(p_bookings)
  LOOP
    v_booking_id := (v_booking->>'booking_id')::UUID;

    SELECT COUNT(*) INTO v_count
    FROM   bookings
    WHERE  id        = v_booking_id
      AND  vendor_id = p_vendor_id
      AND  status    = 'completed';

    IF v_count = 0 THEN
      RAISE EXCEPTION 'Booking % is not a completed booking for vendor %',
                      v_booking_id, p_vendor_id;
    END IF;

    -- Only DODO-collected payments are eligible for settlement.
    SELECT payment_method INTO v_pay_method
    FROM   bookings
    WHERE  id = v_booking_id;

    IF NOT is_online_payment(v_pay_method) THEN
      RAISE EXCEPTION
        'Booking % has payment method ''%'' — only Razorpay and DODO UPI bookings '
        'are eligible for vendor settlement. Cash/COD/Vendor UPI bookings are '
        'settled by wallet commission.',
        v_booking_id, COALESCE(v_pay_method, 'unknown');
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM   vendor_settlement_bookings
    WHERE  booking_id = v_booking_id;

    IF v_count > 0 THEN
      RAISE EXCEPTION 'Booking % has already been settled', v_booking_id;
    END IF;

    v_total_amount := v_total_amount + (v_booking->>'net_vendor_amount')::NUMERIC;
  END LOOP;

  INSERT INTO vendor_settlements (
    vendor_id, vendor_name, amount, completed_jobs_count,
    payment_method, reference_number, notes, settled_by, settled_at
  ) VALUES (
    p_vendor_id,
    p_vendor_name,
    v_total_amount,
    jsonb_array_length(p_bookings),
    NULLIF(p_payment_method, ''),
    NULLIF(p_reference_number, ''),
    NULLIF(p_notes, ''),
    p_settled_by,
    now()
  )
  RETURNING id INTO v_settlement_id;

  FOR v_booking IN SELECT value FROM jsonb_array_elements(p_bookings)
  LOOP
    INSERT INTO vendor_settlement_bookings (
      settlement_id,      booking_id,
      booking_gross,      subtotal_before_tax,
      tax_amount,         commission_base,
      commission_amount,  net_vendor_amount
    ) VALUES (
      v_settlement_id,
      (v_booking->>'booking_id')::UUID,
      (v_booking->>'booking_gross')::NUMERIC,
      (v_booking->>'subtotal_before_tax')::NUMERIC,
      (v_booking->>'tax_amount')::NUMERIC,
      (v_booking->>'commission_base')::NUMERIC,
      (v_booking->>'commission_amount')::NUMERIC,
      (v_booking->>'net_vendor_amount')::NUMERIC
    );
  END LOOP;

  RETURN v_settlement_id;
END;
$$;

-- ── 7. Insert default upi_dodo gateway config (disabled by default) ───────────

INSERT INTO payment_gateway_configs (gateway, is_enabled, mode, display_name, public_key, extra_config)
VALUES (
  'upi_dodo',
  false,
  'live',
  'DODO Booker UPI',
  '',
  '{"upi_id": "", "qr_image_url": ""}'::jsonb
)
ON CONFLICT (gateway) DO NOTHING;
