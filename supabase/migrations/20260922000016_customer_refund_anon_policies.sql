-- ─────────────────────────────────────────────────────────────────────────────
-- Customer Refund: Anon Role Access + RPC Updates
--
-- Context:
--   The customer app uses a custom phone-OTP flow (dev_auth table) instead of
--   Supabase Auth.  The Flutter client runs as the `anon` role with no Supabase
--   JWT — auth.uid() is always NULL for customer requests.  The policies and
--   RPCs in migration 20260922000015 used `TO authenticated` and auth.uid(),
--   which is the correct model for admin users but does not work for customers.
--
-- This migration:
--   1. Adds `anon` SELECT policies on all six refund tables so customers can
--      read data.  Client-side customer_id filtering enforces ownership (same
--      security model as the existing bookings, booking_payments, etc.).
--   2. Replaces the customer RPCs with versions that accept p_customer_id from
--      the client and verify it server-side against the booking/request, rather
--      than relying on auth.uid().
--   3. Grants both RPCs to the `anon` role.
--
-- The existing `TO authenticated` policies and admin-scoped policies are kept
-- intact so the Admin Panel and future Supabase Auth migration are unaffected.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── refund_requests: anon SELECT ─────────────────────────────────────────────

DROP POLICY IF EXISTS "anon_select_own_refund_requests" ON refund_requests;
CREATE POLICY "anon_select_own_refund_requests"
  ON refund_requests FOR SELECT
  TO anon
  USING (true);
-- Ownership enforced client-side: Flutter filters by customer_id derived from
-- the locally stored phone, identical to the bookings/booking_payments pattern.

-- ── refund_status_history: anon SELECT ───────────────────────────────────────

DROP POLICY IF EXISTS "anon_select_refund_status_history" ON refund_status_history;
CREATE POLICY "anon_select_refund_status_history"
  ON refund_status_history FOR SELECT
  TO anon
  USING (true);

-- ── refund_transactions: anon SELECT ─────────────────────────────────────────

DROP POLICY IF EXISTS "anon_select_refund_transactions" ON refund_transactions;
CREATE POLICY "anon_select_refund_transactions"
  ON refund_transactions FOR SELECT
  TO anon
  USING (true);

-- ── refund_messages: anon SELECT (non-internal only) ─────────────────────────

DROP POLICY IF EXISTS "anon_select_refund_messages" ON refund_messages;
CREATE POLICY "anon_select_refund_messages"
  ON refund_messages FOR SELECT
  TO anon
  USING (is_internal = FALSE);

-- ── refund_issue_categories: anon SELECT ─────────────────────────────────────

DROP POLICY IF EXISTS "anon_select_active_refund_issue_categories" ON refund_issue_categories;
CREATE POLICY "anon_select_active_refund_issue_categories"
  ON refund_issue_categories FOR SELECT
  TO anon
  USING (is_active = TRUE);

-- ── refund_policies: anon SELECT ─────────────────────────────────────────────

DROP POLICY IF EXISTS "anon_select_active_refund_policies" ON refund_policies;
CREATE POLICY "anon_select_active_refund_policies"
  ON refund_policies FOR SELECT
  TO anon
  USING (is_active = TRUE);

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: customer_create_refund_request (updated for anon auth model)
--
-- Changes from 20260922000015 version:
--   • Accepts p_customer_id UUID from the client (replaces auth.uid() lookup).
--   • Verifies p_customer_id exists in customers and is active.
--   • Verifies the booking belongs to that customer — server enforces ownership.
--   • Granted to both anon (customer app) and authenticated (future Supabase Auth).
--
-- Security: p_customer_id is the customers.id UUID obtained by the Flutter app
-- after verifying the phone OTP against dev_auth.  The server verifies this ID
-- exists AND that the requested booking belongs to it.  This is the same level
-- of protection used throughout the existing customer-facing API surface.
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
  -- Prefer auth.uid() (Supabase Auth, used by admin / future migration).
  -- Fall back to the explicitly supplied p_customer_id (anon / dev_auth flow).
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

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: customer_add_refund_message (updated for anon auth model)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION customer_add_refund_message(
  p_request_id     UUID,
  p_message        TEXT,
  p_attachment_url TEXT DEFAULT NULL,
  p_customer_id    UUID DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_customer_id UUID;
  v_request     RECORD;
BEGIN
  -- Resolve customer identity (same dual-mode pattern as above).
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

  IF p_message IS NULL OR TRIM(p_message) = '' THEN
    RAISE EXCEPTION 'Message cannot be empty'
      USING ERRCODE = 'P0001';
  END IF;

  -- Validate request belongs to customer and is not closed.
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

GRANT EXECUTE ON FUNCTION customer_add_refund_message(UUID, TEXT, TEXT, UUID)
  TO anon, authenticated;
