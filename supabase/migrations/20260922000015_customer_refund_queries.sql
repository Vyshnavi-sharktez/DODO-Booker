-- ─────────────────────────────────────────────────────────────────────────────
-- Customer App Refund Queries
--
-- Adds RLS policies for authenticated customers to access their own refund data,
-- and two SECURITY DEFINER RPCs for safe customer mutations:
--
--   customer_create_refund_request  — submits a refund ticket
--   customer_add_refund_message     — sends a message on a ticket thread
--
-- Existing admin and service_role policies are untouched.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Helper: resolve authenticated customer's UUID ─────────────────────────────
-- Used inline in policies via EXISTS subquery.
-- Pattern: customers.auth_user_id = auth.uid()

-- ── refund_requests: customer SELECT ─────────────────────────────────────────

DROP POLICY IF EXISTS "customer_select_own_refund_requests" ON refund_requests;
CREATE POLICY "customer_select_own_refund_requests"
  ON refund_requests FOR SELECT
  TO authenticated
  USING (
    customer_id = (
      SELECT id FROM customers
       WHERE auth_user_id = auth.uid()
         AND is_active = TRUE
      LIMIT 1
    )
  );

-- ── refund_status_history: customer SELECT ────────────────────────────────────

DROP POLICY IF EXISTS "customer_select_own_refund_status_history" ON refund_status_history;
CREATE POLICY "customer_select_own_refund_status_history"
  ON refund_status_history FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM refund_requests rr
       WHERE rr.id   = refund_status_history.refund_request_id
         AND rr.customer_id = (
               SELECT id FROM customers
                WHERE auth_user_id = auth.uid()
                  AND is_active = TRUE
               LIMIT 1
             )
    )
  );

-- ── refund_transactions: customer SELECT ──────────────────────────────────────

DROP POLICY IF EXISTS "customer_select_own_refund_transactions" ON refund_transactions;
CREATE POLICY "customer_select_own_refund_transactions"
  ON refund_transactions FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM refund_requests rr
       WHERE rr.id = refund_transactions.refund_request_id
         AND rr.customer_id = (
               SELECT id FROM customers
                WHERE auth_user_id = auth.uid()
                  AND is_active = TRUE
               LIMIT 1
             )
    )
  );

-- ── refund_messages: customer SELECT (own tickets, non-internal only) ─────────

DROP POLICY IF EXISTS "customer_select_own_refund_messages" ON refund_messages;
CREATE POLICY "customer_select_own_refund_messages"
  ON refund_messages FOR SELECT
  TO authenticated
  USING (
    is_internal = FALSE
    AND EXISTS (
      SELECT 1 FROM refund_requests rr
       WHERE rr.id = refund_messages.refund_request_id
         AND rr.customer_id = (
               SELECT id FROM customers
                WHERE auth_user_id = auth.uid()
                  AND is_active = TRUE
               LIMIT 1
             )
    )
  );

-- ── refund_issue_categories: authenticated SELECT ─────────────────────────────

DROP POLICY IF EXISTS "customer_select_active_refund_issue_categories" ON refund_issue_categories;
CREATE POLICY "customer_select_active_refund_issue_categories"
  ON refund_issue_categories FOR SELECT
  TO authenticated
  USING (is_active = TRUE);

-- ── refund_policies: authenticated SELECT ─────────────────────────────────────

DROP POLICY IF EXISTS "customer_select_active_refund_policies" ON refund_policies;
CREATE POLICY "customer_select_active_refund_policies"
  ON refund_policies FOR SELECT
  TO authenticated
  USING (is_active = TRUE);

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: customer_create_refund_request
--
-- Called by the customer app to submit a refund ticket.
--
-- Security:
--   • SECURITY DEFINER (bypasses RLS for internal tables)
--   • GRANT TO authenticated only — requires a signed-in user
--   • Derives customer_id from auth.uid() → NOT trusted from client
--   • Validates booking belongs to that customer
--   • Looks up payment context from bookings + booking_payments tables
--   • Does NOT initiate any money movement
--
-- Returns: JSONB with { id, ticket_number }
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION customer_create_refund_request(
  p_booking_id         UUID,
  p_issue_category_id  UUID,
  p_description        TEXT,
  p_requested_amount   NUMERIC,
  p_evidence_urls      JSONB DEFAULT '[]'::JSONB
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
  -- Resolve authenticated customer from JWT
  SELECT id INTO v_customer_id
    FROM customers
   WHERE auth_user_id = auth.uid()
     AND is_active = TRUE
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated customer not found'
      USING ERRCODE = '42501';
  END IF;

  -- Validate booking exists and belongs to this customer
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

  -- Validate amount
  IF p_requested_amount <= 0 THEN
    RAISE EXCEPTION 'Requested amount must be greater than 0'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_requested_amount > v_total_amount THEN
    RAISE EXCEPTION 'Requested amount exceeds amount paid'
      USING ERRCODE = 'P0001';
  END IF;

  -- Resolve payment context
  -- For online bookings, find the successful booking_payments row.
  -- For COD/cash, payment_id stays NULL.
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

  -- Insert refund request (ticket_number auto-generated by trigger)
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
    '',                    -- overwritten by trigger
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

  -- Initial status history entry
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

GRANT EXECUTE ON FUNCTION customer_create_refund_request(UUID, UUID, TEXT, NUMERIC, JSONB)
  TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: customer_add_refund_message
--
-- Called by the customer app to post a message on a refund ticket thread.
--
-- Security:
--   • SECURITY DEFINER
--   • GRANT TO authenticated only
--   • Validates the request belongs to the authenticated customer
--   • Prevents posting to resolved/closed tickets (admin can always message)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION customer_add_refund_message(
  p_request_id    UUID,
  p_message       TEXT,
  p_attachment_url TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_customer_id UUID;
  v_request     RECORD;
BEGIN
  -- Resolve customer
  SELECT id INTO v_customer_id
    FROM customers
   WHERE auth_user_id = auth.uid()
     AND is_active = TRUE
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated customer not found'
      USING ERRCODE = '42501';
  END IF;

  -- Validate message not empty
  IF p_message IS NULL OR TRIM(p_message) = '' THEN
    RAISE EXCEPTION 'Message cannot be empty'
      USING ERRCODE = 'P0001';
  END IF;

  -- Validate request belongs to customer and is not in a terminal state
  SELECT id, status INTO v_request
    FROM refund_requests
   WHERE id = p_request_id
     AND customer_id = v_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request not found or does not belong to this customer'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status = 'closed' THEN
    RAISE EXCEPTION 'Cannot send message on a closed refund request'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO refund_messages (
    refund_request_id,
    sender_type,
    sender_id,
    message,
    attachment_url,
    is_internal
  ) VALUES (
    p_request_id,
    'customer',
    v_customer_id,
    TRIM(p_message),
    NULLIF(TRIM(COALESCE(p_attachment_url, '')), ''),
    FALSE
  );
END;
$$;

GRANT EXECUTE ON FUNCTION customer_add_refund_message(UUID, TEXT, TEXT)
  TO authenticated;
