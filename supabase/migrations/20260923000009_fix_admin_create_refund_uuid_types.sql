-- ─────────────────────────────────────────────────────────────────────────────
-- Fix admin_create_refund_request: v_admin_user_id TEXT → UUID
--
-- The original function (000006) declared v_admin_user_id as TEXT and cast
-- auth.uid()::TEXT.  refund_status_history.changed_by and
-- refund_messages.sender_id are both UUID columns, so PostgreSQL raises
-- "column is of type uuid but expression is of type text" on INSERT.
-- ─────────────────────────────────────────────────────────────────────────────

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
  v_payment_method     TEXT;
  v_total_amount       NUMERIC;
  v_payment_id         UUID;
  v_amount_paid        NUMERIC;
  v_payment_snapshot   TEXT;
  v_request_id         UUID;
  v_ticket_number      TEXT;
  v_admin_user_id      UUID;
BEGIN
  PERFORM fn_assert_active_admin();
  v_admin_user_id := auth.uid();

  IF NOT EXISTS (
    SELECT 1 FROM customers WHERE id = p_customer_id AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Customer not found or inactive'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT customer_id,
         COALESCE(payment_method, 'cash'),
         total_amount
    INTO v_booking_customer, v_payment_method, v_total_amount
    FROM bookings
   WHERE id = p_booking_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_booking_customer <> p_customer_id THEN
    RAISE EXCEPTION 'Booking does not belong to this customer'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM service_warranties WHERE rework_booking_id = p_booking_id
  ) THEN
    RAISE EXCEPTION 'Warranty rework bookings are not eligible for refunds'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM refund_requests
     WHERE booking_id = p_booking_id
       AND status NOT IN ('rejected', 'closed')
  ) THEN
    RAISE EXCEPTION 'An active refund request already exists for this booking'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_requested_amount <= 0 THEN
    RAISE EXCEPTION 'Requested amount must be greater than 0'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_payment_method IN ('online', 'razorpay') THEN
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
