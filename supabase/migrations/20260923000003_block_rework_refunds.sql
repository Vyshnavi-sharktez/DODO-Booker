-- ─────────────────────────────────────────────────────────────────────────────
-- Block warranty rework bookings from refund requests
--
-- Warranty rework bookings are booked at ₹0 cost and represent a re-service
-- under an existing warranty claim. Customers must not be able to raise refund
-- requests against them because there is nothing to refund.
--
-- The indicator is: EXISTS (
--   SELECT 1 FROM service_warranties WHERE rework_booking_id = p_booking_id
-- )
-- There is no is_rework column on bookings; the relationship lives on
-- service_warranties.
--
-- This migration replaces customer_create_refund_request (last updated in
-- 20260922000016) to add a rework check immediately after booking-ownership
-- validation. All other behaviour is unchanged.
-- ─────────────────────────────────────────────────────────────────────────────

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
BEGIN
  -- Resolve customer identity.
  -- Prefer auth.uid() (Supabase Auth, admin / future migration).
  -- Fall back to p_customer_id (anon / dev_auth flow).
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
         COALESCE(payment_method, 'cash')
    INTO v_booking_customer, v_booking_status, v_total_amount, v_payment_method
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

  -- Block warranty rework bookings.
  IF EXISTS (
    SELECT 1 FROM service_warranties
     WHERE rework_booking_id = p_booking_id
  ) THEN
    RAISE EXCEPTION 'Warranty rework bookings are not eligible for refunds'
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
