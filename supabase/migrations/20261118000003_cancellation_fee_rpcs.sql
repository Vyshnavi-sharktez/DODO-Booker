-- ─────────────────────────────────────────────────────────────────────────────
-- Dynamic Customer Cancellation Fee System — RPCs
-- ─────────────────────────────────────────────────────────────────────────────

-- Drop old stubs whose return types changed (created in previous partial migration)
DROP FUNCTION IF EXISTS calculate_cancellation_fee(UUID);
DROP FUNCTION IF EXISTS cancel_booking_with_fee(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS get_pending_cancellation_fees(UUID);
DROP FUNCTION IF EXISTS mark_cancellation_fees_collected(UUID);

-- ── calculate_cancellation_fee ───────────────────────────────────────────────
-- Returns the fee that would be charged if the booking is cancelled now.
-- Looks up the applicable policy (before/after assignment) and finds the
-- matching time slab.
--
-- Returns JSONB:
--   fee_amount     NUMERIC   – fee in ₹ (0 = free)
--   reason_message TEXT      – human-readable explanation
--   is_cod         BOOL      – payment method is cash-on-delivery
--   payment_method TEXT      – 'cod' | 'online' | 'razorpay' | ...
--   payment_amount NUMERIC   – amount paid (0 for COD)
--   refund_amount  NUMERIC   – payment_amount - fee (0 for COD)

CREATE OR REPLACE FUNCTION calculate_cancellation_fee(p_booking_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_customer_id    UUID;
  v_booking        RECORD;
  v_policy_type    TEXT;
  v_policy         RECORD;
  v_slab           RECORD;
  v_time_value     NUMERIC;
  v_fee_amount     NUMERIC    := 0;
  v_payment_amount NUMERIC    := 0;
  v_refund_amount  NUMERIC    := 0;
  v_scheduled_dt   TIMESTAMPTZ;
  v_reason_msg     TEXT       := 'Free cancellation';
BEGIN
  -- Resolve caller's customer record
  SELECT id INTO v_customer_id FROM customers WHERE auth_user_id = auth.uid();
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  -- Fetch the booking (ownership check included)
  SELECT b.id, b.status, b.vendor_id, b.payment_method, b.payment_status,
         b.total_amount, b.created_at, b.service_date, b.scheduled_time
    INTO v_booking
    FROM bookings b
   WHERE b.id = p_booking_id AND b.customer_id = v_customer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  -- Determine which policy applies
  v_policy_type := CASE
    WHEN v_booking.vendor_id IS NULL THEN 'before_assignment'
    ELSE 'after_assignment'
  END;

  -- Fetch the policy row
  SELECT * INTO v_policy
    FROM cancellation_policies
   WHERE policy_type = v_policy_type;

  -- If policy is disabled or doesn't exist, fee = 0
  IF FOUND AND v_policy.is_enabled THEN

    IF v_policy_type = 'before_assignment' THEN
      -- Elapsed minutes since booking was placed
      v_time_value := EXTRACT(EPOCH FROM (NOW() - v_booking.created_at)) / 60.0;

    ELSE
      -- Remaining minutes until scheduled service
      BEGIN
        v_scheduled_dt := v_booking.service_date::DATE + v_booking.scheduled_time::TIME;
      EXCEPTION WHEN OTHERS THEN
        v_scheduled_dt := NULL;
      END;

      IF v_scheduled_dt IS NOT NULL THEN
        v_time_value := GREATEST(0, EXTRACT(EPOCH FROM (v_scheduled_dt - NOW())) / 60.0);
      END IF;
    END IF;

    IF v_time_value IS NOT NULL THEN
      -- Find matching slab: time_value >= from_minutes AND (to_minutes IS NULL OR time_value < to_minutes)
      SELECT * INTO v_slab
        FROM cancellation_policy_slabs
       WHERE policy_id = v_policy.id
         AND from_minutes <= v_time_value
         AND (to_minutes IS NULL OR v_time_value < to_minutes)
       ORDER BY sort_order, from_minutes
       LIMIT 1;

      IF FOUND AND v_slab.fee_amount > 0 THEN
        v_fee_amount := v_slab.fee_amount;
        v_reason_msg := COALESCE(
          v_slab.label,
          CASE v_policy_type
            WHEN 'before_assignment' THEN 'Late cancellation fee'
            ELSE 'Short notice cancellation fee'
          END
        );
      END IF;
    END IF;
  END IF;

  -- Compute online refund amount
  IF v_booking.payment_method IN ('online', 'razorpay')
     AND v_booking.payment_status = 'success' THEN
    SELECT COALESCE(bp.amount, v_booking.total_amount)
      INTO v_payment_amount
      FROM booking_payments bp
     WHERE bp.booking_id = p_booking_id AND bp.status = 'success'
     ORDER BY bp.attempt_number DESC
     LIMIT 1;
    v_payment_amount := COALESCE(v_payment_amount, v_booking.total_amount, 0);
    v_refund_amount  := GREATEST(0, v_payment_amount - v_fee_amount);
  END IF;

  RETURN jsonb_build_object(
    'fee_amount',      v_fee_amount,
    'reason_message',  v_reason_msg,
    'is_cod',          v_booking.payment_method = 'cod',
    'payment_method',  COALESCE(v_booking.payment_method, ''),
    'payment_amount',  v_payment_amount,
    'refund_amount',   v_refund_amount
  );
END;
$$;

-- ── cancel_booking_with_fee ───────────────────────────────────────────────────
-- Atomically cancels the booking and records the applicable cancellation fee.
-- For online payments: fee is deducted from the auto-refund (via trigger).
-- For COD: fee is marked as uncollected; collected at next checkout.
--
-- Returns JSONB: { success, cancellation_fee_amount, refund_amount, is_cod }

CREATE OR REPLACE FUNCTION cancel_booking_with_fee(
  p_booking_id UUID,
  p_reason     TEXT DEFAULT NULL,
  p_remarks    TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_customer_id    UUID;
  v_booking        RECORD;
  v_policy_type    TEXT;
  v_policy         RECORD;
  v_slab           RECORD;
  v_time_value     NUMERIC;
  v_fee_amount     NUMERIC    := 0;
  v_payment_amount NUMERIC    := 0;
  v_refund_amount  NUMERIC    := 0;
  v_scheduled_dt   TIMESTAMPTZ;
BEGIN
  SELECT id INTO v_customer_id FROM customers WHERE auth_user_id = auth.uid();
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  -- Lock the row to prevent concurrent cancellations
  SELECT b.id, b.status, b.vendor_id, b.payment_method, b.payment_status,
         b.total_amount, b.created_at, b.service_date, b.scheduled_time
    INTO v_booking
    FROM bookings b
   WHERE b.id = p_booking_id AND b.customer_id = v_customer_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  -- Only allow cancellation for active, non-dispatched statuses
  IF v_booking.status NOT IN ('pending', 'assigned', 'assignedToDodoTeam', 'accepted') THEN
    RAISE EXCEPTION 'Booking cannot be cancelled in status: %', v_booking.status;
  END IF;

  -- ── Calculate fee (same logic as calculate_cancellation_fee) ────────────────
  v_policy_type := CASE
    WHEN v_booking.vendor_id IS NULL THEN 'before_assignment'
    ELSE 'after_assignment'
  END;

  SELECT * INTO v_policy
    FROM cancellation_policies
   WHERE policy_type = v_policy_type;

  IF FOUND AND v_policy.is_enabled THEN
    IF v_policy_type = 'before_assignment' THEN
      v_time_value := EXTRACT(EPOCH FROM (NOW() - v_booking.created_at)) / 60.0;
    ELSE
      BEGIN
        v_scheduled_dt := v_booking.service_date::DATE + v_booking.scheduled_time::TIME;
      EXCEPTION WHEN OTHERS THEN
        v_scheduled_dt := NULL;
      END;
      IF v_scheduled_dt IS NOT NULL THEN
        v_time_value := GREATEST(0, EXTRACT(EPOCH FROM (v_scheduled_dt - NOW())) / 60.0);
      END IF;
    END IF;

    IF v_time_value IS NOT NULL THEN
      SELECT * INTO v_slab
        FROM cancellation_policy_slabs
       WHERE policy_id = v_policy.id
         AND from_minutes <= v_time_value
         AND (to_minutes IS NULL OR v_time_value < to_minutes)
       ORDER BY sort_order, from_minutes
       LIMIT 1;
      IF FOUND THEN
        v_fee_amount := v_slab.fee_amount;
      END IF;
    END IF;
  END IF;
  -- ── End fee calculation ──────────────────────────────────────────────────────

  -- Compute refund for online payments
  IF v_booking.payment_method IN ('online', 'razorpay')
     AND v_booking.payment_status = 'success' THEN
    SELECT COALESCE(bp.amount, v_booking.total_amount)
      INTO v_payment_amount
      FROM booking_payments bp
     WHERE bp.booking_id = p_booking_id AND bp.status = 'success'
     ORDER BY bp.attempt_number DESC
     LIMIT 1;
    v_payment_amount := COALESCE(v_payment_amount, v_booking.total_amount, 0);
    v_refund_amount  := GREATEST(0, v_payment_amount - v_fee_amount);
  END IF;

  -- Atomically cancel: set status, record fee, mark COD fee as pending
  UPDATE bookings
     SET status                    = 'cancelled_by_customer',
         cancellation_fee_amount   = v_fee_amount,
         -- For non-COD: fee is handled via refund deduction → already "collected"
         -- For COD: fee is pending → collected at next checkout
         cancellation_fee_collected = (v_booking.payment_method != 'cod' OR v_fee_amount = 0),
         cancellation_remarks      = COALESCE(p_remarks, p_reason)
   WHERE id = p_booking_id;

  RETURN jsonb_build_object(
    'success',                 TRUE,
    'cancellation_fee_amount', v_fee_amount,
    'refund_amount',           v_refund_amount,
    'is_cod',                  v_booking.payment_method = 'cod'
  );
END;
$$;

-- ── get_pending_cancellation_fees ─────────────────────────────────────────────
-- Returns the total uncollected COD cancellation fees for the current customer.
-- Called from checkout to show and collect outstanding fees.

CREATE OR REPLACE FUNCTION get_pending_cancellation_fees()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_customer_id   UUID;
  v_total_fee     NUMERIC := 0;
  v_booking_count INTEGER := 0;
BEGIN
  SELECT id INTO v_customer_id FROM customers WHERE auth_user_id = auth.uid();
  IF v_customer_id IS NULL THEN
    RETURN jsonb_build_object('total_pending_fee', 0, 'booking_count', 0);
  END IF;

  SELECT COALESCE(SUM(cancellation_fee_amount), 0),
         COUNT(*)::INTEGER
    INTO v_total_fee, v_booking_count
    FROM bookings
   WHERE customer_id              = v_customer_id
     AND cancellation_fee_collected = FALSE
     AND cancellation_fee_amount  > 0
     AND payment_method           = 'cod';

  RETURN jsonb_build_object(
    'total_pending_fee', v_total_fee,
    'booking_count',     v_booking_count
  );
END;
$$;

-- ── mark_cancellation_fees_collected ─────────────────────────────────────────
-- Marks all pending COD cancellation fees as collected after a successful booking.

CREATE OR REPLACE FUNCTION mark_cancellation_fees_collected()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_customer_id UUID;
BEGIN
  SELECT id INTO v_customer_id FROM customers WHERE auth_user_id = auth.uid();
  IF v_customer_id IS NULL THEN RETURN; END IF;

  UPDATE bookings
     SET cancellation_fee_collected = TRUE
   WHERE customer_id              = v_customer_id
     AND cancellation_fee_collected = FALSE
     AND cancellation_fee_amount  > 0
     AND payment_method           = 'cod';
END;
$$;

-- ── admin_get_cancellation_policies ──────────────────────────────────────────
-- Returns both policies with their slabs for the admin panel.

CREATE OR REPLACE FUNCTION admin_get_cancellation_policies()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',          p.id,
      'policy_type', p.policy_type,
      'is_enabled',  p.is_enabled,
      'label',       p.label,
      'description', p.description,
      'updated_at',  p.updated_at,
      'slabs',       COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'id',           s.id,
            'from_minutes', s.from_minutes,
            'to_minutes',   s.to_minutes,
            'fee_amount',   s.fee_amount,
            'label',        s.label,
            'sort_order',   s.sort_order
          ) ORDER BY s.sort_order, s.from_minutes
        )
        FROM cancellation_policy_slabs s
        WHERE s.policy_id = p.id
      ), '[]'::JSONB)
    ) ORDER BY p.policy_type
  )
  INTO v_result
  FROM cancellation_policies p;

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

-- ── admin_toggle_cancellation_policy ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_toggle_cancellation_policy(
  p_policy_id UUID,
  p_is_enabled BOOLEAN
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE cancellation_policies
     SET is_enabled = p_is_enabled, updated_at = NOW()
   WHERE id = p_policy_id;
END;
$$;

-- ── admin_upsert_cancellation_slab ───────────────────────────────────────────
-- Creates a new slab (p_id IS NULL) or updates an existing one.
-- Returns the slab's UUID.

CREATE OR REPLACE FUNCTION admin_upsert_cancellation_slab(
  p_policy_id    UUID,
  p_id           UUID    DEFAULT NULL,
  p_from_minutes INTEGER DEFAULT 0,
  p_to_minutes   INTEGER DEFAULT NULL,
  p_fee_amount   NUMERIC DEFAULT 0,
  p_label        TEXT    DEFAULT NULL,
  p_sort_order   INTEGER DEFAULT 0
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_id IS NOT NULL THEN
    UPDATE cancellation_policy_slabs
       SET from_minutes = p_from_minutes,
           to_minutes   = p_to_minutes,
           fee_amount   = p_fee_amount,
           label        = p_label,
           sort_order   = p_sort_order
     WHERE id = p_id AND policy_id = p_policy_id
     RETURNING id INTO v_id;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  END IF;

  INSERT INTO cancellation_policy_slabs
    (policy_id, from_minutes, to_minutes, fee_amount, label, sort_order)
  VALUES
    (p_policy_id, p_from_minutes, p_to_minutes, p_fee_amount, p_label, p_sort_order)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ── admin_delete_cancellation_slab ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_delete_cancellation_slab(p_slab_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM cancellation_policy_slabs WHERE id = p_slab_id;
END;
$$;
