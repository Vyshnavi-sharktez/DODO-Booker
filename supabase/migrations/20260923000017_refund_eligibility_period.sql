-- ─────────────────────────────────────────────────────────────────────────────
-- Refund Eligibility Period — two-level configuration.
--
-- customer_create_refund_request and admin_create_refund_request are updated to
-- enforce a configurable refund eligibility window:
--
--   Effective period resolution order (most → least specific):
--     1. catalog_node_configs 'refund' module for the booked service
--        (walks the catalog hierarchy via resolve_catalog_module_config)
--     2. settings table key 'default_refund_period_days'
--     3. Hard-coded fallback: 30 days
--
--   Eligibility rule:
--     • Applies only to COMPLETED bookings. The period is measured from
--       bookings.completed_at (set in migration 000015).
--     • CANCELLED bookings are not subject to the completed-service period.
--       Online cancelled bookings with a captured payment remain eligible
--       regardless of how long ago they were cancelled.
--     • A request submitted within the valid period remains valid even if the
--       period expires before admin review or processing is complete.  This
--       function only gates NEW request creation.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Helper: resolve effective refund period for a booking ─────────────────────
--
-- Returns the number of days within which a refund request may be submitted
-- after a completed booking.  Resolution order: catalog scoped config →
-- global settings → hard-coded 30.

CREATE OR REPLACE FUNCTION resolve_refund_period_days(
  p_booking_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_service_id   UUID;
  v_parent_id    UUID;
  v_scoped_cfg   JSONB;
  v_global_days  TEXT;
  v_days         INTEGER;
BEGIN
  -- Resolve service node and parent context from the first booking_item.
  SELECT bi.service_id, bi.catalog_parent_node_id
    INTO v_service_id, v_parent_id
    FROM booking_items bi
   WHERE bi.booking_id = p_booking_id
     AND bi.service_id IS NOT NULL
   LIMIT 1;

  -- If a service is found, try the catalog scoped config first.
  IF v_service_id IS NOT NULL THEN
    v_scoped_cfg := resolve_catalog_module_config(
      'refund', v_service_id, v_parent_id
    );
    IF v_scoped_cfg IS NOT NULL THEN
      v_days := (v_scoped_cfg ->> 'refund_period_days')::INTEGER;
      IF v_days IS NOT NULL AND v_days >= 0 THEN
        RETURN v_days;
      END IF;
    END IF;
  END IF;

  -- Fall back to the global setting.
  SELECT setting_value
    INTO v_global_days
    FROM settings
   WHERE setting_key = 'default_refund_period_days';

  IF v_global_days IS NOT NULL THEN
    v_days := v_global_days::INTEGER;
    IF v_days IS NOT NULL AND v_days >= 0 THEN
      RETURN v_days;
    END IF;
  END IF;

  -- Hard-coded safety fallback.
  RETURN 30;
END;
$$;

GRANT EXECUTE ON FUNCTION resolve_refund_period_days(UUID) TO anon, authenticated;

-- ── customer_create_refund_request — add period check ────────────────────────

CREATE OR REPLACE FUNCTION customer_create_refund_request(
  p_booking_id         UUID,
  p_issue_category_id  UUID,
  p_description        TEXT,
  p_requested_amount   NUMERIC,
  p_evidence_urls      JSONB    DEFAULT '[]'::JSONB,
  p_customer_id        UUID     DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_customer_id        UUID;
  v_booking_status     TEXT;
  v_booking_customer   UUID;
  v_payment_method     TEXT;
  v_total_amount       NUMERIC;
  v_payment_id         UUID;
  v_amount_paid        NUMERIC;
  v_payment_snapshot   TEXT;
  v_request_id         UUID;
  v_ticket_number      TEXT;
  v_evidence_count     SMALLINT;
  v_completed_at       TIMESTAMPTZ;
  v_period_days        INTEGER;
BEGIN
  -- Resolve customer identity.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_customer_id
      FROM customers
     WHERE auth_user_id = auth.uid()
       AND is_active = TRUE
     LIMIT 1;
  ELSIF p_customer_id IS NOT NULL THEN
    SELECT id INTO v_customer_id
      FROM customers
     WHERE id = p_customer_id
       AND is_active = TRUE
     LIMIT 1;
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated customer not found'
      USING ERRCODE = '42501';
  END IF;

  -- Validate booking exists and belongs to this customer.
  SELECT customer_id, status, total_amount,
         COALESCE(payment_method, 'cash'),
         completed_at
    INTO v_booking_customer, v_booking_status, v_total_amount,
         v_payment_method, v_completed_at
    FROM bookings
   WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_booking_customer <> v_customer_id THEN
    RAISE EXCEPTION 'Booking does not belong to this customer'
      USING ERRCODE = '42501';
  END IF;

  -- Block cancelled COD bookings: no payment was ever collected.
  IF v_booking_status = 'cancelled'
     AND v_payment_method IN ('cod', 'cash') THEN
    RAISE EXCEPTION
      'No refund required — COD bookings cancelled before service delivery have no payment to return'
      USING ERRCODE = 'P0001';
  END IF;

  -- Refund eligibility period — applies only to COMPLETED bookings.
  -- Cancelled online bookings (Razorpay payment captured) bypass this check
  -- because the period is measured from service *completion*, not cancellation.
  IF v_booking_status = 'completed' AND v_completed_at IS NOT NULL THEN
    v_period_days := resolve_refund_period_days(p_booking_id);
    IF NOW() > v_completed_at + (v_period_days || ' days')::INTERVAL THEN
      RAISE EXCEPTION
        'Refund period has expired — refund requests must be submitted within % day(s) of service completion',
        v_period_days
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Block if a refund has already been fully processed for this booking.
  IF EXISTS (
    SELECT 1
      FROM refund_requests rr
      JOIN refund_transactions rt ON rt.refund_request_id = rr.id
     WHERE rr.booking_id = p_booking_id
       AND rt.status = 'completed'
  ) THEN
    RAISE EXCEPTION
      'A refund has already been processed for this booking'
      USING ERRCODE = 'P0001';
  END IF;

  -- Validate amount.
  IF p_requested_amount <= 0 THEN
    RAISE EXCEPTION 'Requested amount must be greater than 0'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_requested_amount > v_total_amount THEN
    RAISE EXCEPTION 'Requested amount exceeds amount paid'
      USING ERRCODE = 'P0001';
  END IF;

  -- Resolve payment context.
  IF v_payment_method = 'online' THEN
    SELECT bp.id, bp.amount
      INTO v_payment_id, v_amount_paid
      FROM booking_payments bp
     WHERE bp.booking_id = p_booking_id
       AND bp.status = 'success'
     ORDER BY bp.attempt_number DESC
     LIMIT 1;
    IF v_amount_paid IS NULL THEN
      v_amount_paid := v_total_amount;
    END IF;
    v_payment_snapshot := 'online';
  ELSE
    v_payment_id := NULL;
    v_amount_paid := v_total_amount;
    v_payment_snapshot := CASE v_payment_method
      WHEN 'cod'  THEN 'cod'
      ELSE 'cash'
    END;
  END IF;

  v_evidence_count := COALESCE(
    jsonb_array_length(p_evidence_urls), 0
  )::SMALLINT;

  -- Insert refund request.
  INSERT INTO refund_requests (
    ticket_number,
    booking_id,
    customer_id,
    payment_id,
    issue_category_id,
    description,
    requested_amount,
    evidence_urls,
    evidence_count,
    payment_method_snapshot,
    amount_paid_snapshot,
    status
  ) VALUES (
    '',
    p_booking_id,
    v_customer_id,
    v_payment_id,
    p_issue_category_id,
    NULLIF(TRIM(p_description), ''),
    p_requested_amount,
    COALESCE(p_evidence_urls, '[]'::JSONB),
    v_evidence_count,
    v_payment_snapshot,
    v_amount_paid,
    'submitted'
  )
  RETURNING id, ticket_number
    INTO v_request_id, v_ticket_number;

  -- Initial status history entry.
  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type
  ) VALUES (
    v_request_id, NULL, 'submitted',
    NULL, 'customer'
  );

  RETURN jsonb_build_object(
    'id',            v_request_id,
    'ticket_number', v_ticket_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION customer_create_refund_request(UUID, UUID, TEXT, NUMERIC, JSONB, UUID)
  TO anon, authenticated;

-- ── admin_create_refund_request — add same period check ──────────────────────
--
-- Admins are subject to the same eligibility window.  This prevents the admin
-- panel from being used to bypass the period for completed bookings.

CREATE OR REPLACE FUNCTION admin_create_refund_request(
  p_booking_id         UUID,
  p_customer_id        UUID,
  p_issue_category_id  UUID,
  p_description        TEXT,
  p_requested_amount   NUMERIC,
  p_notes              TEXT  DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_booking_customer   UUID;
  v_booking_status     TEXT;
  v_payment_method     TEXT;
  v_total_amount       NUMERIC;
  v_payment_id         UUID;
  v_amount_paid        NUMERIC;
  v_payment_snapshot   TEXT;
  v_request_id         UUID;
  v_ticket_number      TEXT;
  v_admin_user_id      TEXT;
  v_completed_at       TIMESTAMPTZ;
  v_period_days        INTEGER;
BEGIN
  -- Verify caller is an active admin.
  PERFORM fn_assert_active_admin();
  v_admin_user_id := auth.uid()::TEXT;

  -- Verify the customer exists and is active.
  IF NOT EXISTS (
    SELECT 1 FROM customers WHERE id = p_customer_id AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Customer not found or inactive'
      USING ERRCODE = 'P0002';
  END IF;

  -- Lock and fetch the booking.
  SELECT customer_id,
         status,
         COALESCE(payment_method, 'cash'),
         total_amount,
         completed_at
    INTO v_booking_customer, v_booking_status, v_payment_method,
         v_total_amount, v_completed_at
    FROM bookings
   WHERE id = p_booking_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found'
      USING ERRCODE = 'P0002';
  END IF;

  -- Verify booking belongs to the supplied customer.
  IF v_booking_customer <> p_customer_id THEN
    RAISE EXCEPTION 'Booking does not belong to this customer'
      USING ERRCODE = '42501';
  END IF;

  -- Block warranty rework bookings.
  IF EXISTS (
    SELECT 1 FROM service_warranties WHERE rework_booking_id = p_booking_id
  ) THEN
    RAISE EXCEPTION 'Warranty rework bookings are not eligible for refunds'
      USING ERRCODE = 'P0001';
  END IF;

  -- Prevent duplicate active tickets.
  IF EXISTS (
    SELECT 1 FROM refund_requests
     WHERE booking_id = p_booking_id
       AND status NOT IN ('rejected', 'closed')
  ) THEN
    RAISE EXCEPTION 'An active refund request already exists for this booking'
      USING ERRCODE = 'P0001';
  END IF;

  -- Refund eligibility period — applies only to COMPLETED bookings.
  IF v_booking_status = 'completed' AND v_completed_at IS NOT NULL THEN
    v_period_days := resolve_refund_period_days(p_booking_id);
    IF NOW() > v_completed_at + (v_period_days || ' days')::INTERVAL THEN
      RAISE EXCEPTION
        'Refund period has expired — refund requests must be submitted within % day(s) of service completion',
        v_period_days
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Validate amount.
  IF p_requested_amount <= 0 THEN
    RAISE EXCEPTION 'Requested amount must be greater than 0'
      USING ERRCODE = 'P0001';
  END IF;

  -- Resolve payment context (mirrors customer_create_refund_request).
  -- 'razorpay' is a legacy value; treat it identically to 'online'.
  IF v_payment_method IN ('online', 'razorpay') THEN
    SELECT bp.id, bp.amount
      INTO v_payment_id, v_amount_paid
      FROM booking_payments bp
     WHERE bp.booking_id = p_booking_id
       AND bp.status = 'success'
     ORDER BY bp.attempt_number DESC
     LIMIT 1;

    -- Fall back to total_amount if no successful payment row exists yet.
    IF v_amount_paid IS NULL THEN
      v_amount_paid := v_total_amount;
    END IF;

    v_payment_snapshot := 'online';
  ELSE
    v_payment_id   := NULL;
    v_amount_paid  := v_total_amount;
    v_payment_snapshot := CASE v_payment_method
      WHEN 'cod'  THEN 'cod'
      ELSE 'cash'
    END;
  END IF;

  IF p_requested_amount > v_amount_paid THEN
    RAISE EXCEPTION 'Requested amount (%) exceeds amount paid (%)',
      p_requested_amount, v_amount_paid
      USING ERRCODE = 'P0001';
  END IF;

  -- Insert the ticket.
  INSERT INTO refund_requests (
    ticket_number,
    booking_id,
    customer_id,
    payment_id,
    issue_category_id,
    description,
    requested_amount,
    evidence_urls,
    evidence_count,
    payment_method_snapshot,
    amount_paid_snapshot,
    status
  ) VALUES (
    '',
    p_booking_id,
    p_customer_id,
    v_payment_id,
    p_issue_category_id,
    NULLIF(TRIM(p_description), ''),
    p_requested_amount,
    '[]'::JSONB,
    0,
    v_payment_snapshot,
    v_amount_paid,
    'submitted'
  )
  RETURNING id, ticket_number
    INTO v_request_id, v_ticket_number;

  -- Status history entry — mark this as admin-initiated.
  INSERT INTO refund_status_history (
    refund_request_id,
    from_status,
    to_status,
    changed_by,
    changed_by_type
  ) VALUES (
    v_request_id,
    NULL,
    'submitted',
    v_admin_user_id,
    'admin'
  );

  -- Optional internal admin note.
  IF p_notes IS NOT NULL AND TRIM(p_notes) <> '' THEN
    INSERT INTO refund_messages (
      refund_request_id,
      sender_type,
      sender_id,
      message,
      is_internal
    ) VALUES (
      v_request_id,
      'admin',
      v_admin_user_id,
      TRIM(p_notes),
      TRUE
    );
  END IF;

  RETURN jsonb_build_object(
    'id',            v_request_id,
    'ticket_number', v_ticket_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_create_refund_request(UUID, UUID, UUID, TEXT, NUMERIC, TEXT)
  TO authenticated;
