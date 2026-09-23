-- ─────────────────────────────────────────────────────────────────────────────
-- COD Bank/UPI Details Collection + Refund Flow Enforcement
--
-- Changes in this migration:
--
--   1. Adds three columns to refund_requests:
--        bank_details_requested_at  — when admin requested bank/UPI details
--        bank_details_submitted_at  — when customer submitted their details
--        bank_upi_details           — the customer-submitted account/UPI details
--                                     (JSONB; admin-only — NOT visible to anon)
--
--   2. Restricts bank_upi_details from the anon role using the same technique
--      as migration 000017 (column-level grants require removing table-level
--      SELECT first, then re-granting safe columns).
--
--   3. admin_request_cod_bank_details — sends a bank/UPI details request to
--      the customer via the messaging system; sets bank_details_requested_at.
--
--   4. customer_submit_bank_upi_details — customer submits their bank account
--      or UPI details; stores in bank_upi_details and sets bank_details_submitted_at.
--
--   5. admin_initiate_refund_transaction — replaces the version from migration
--      000009 with:
--        • COD/cash: forces gateway='manual', refund_method='manual',
--          requires bank_details_submitted_at IS NOT NULL.
--        • Online: forces gateway='razorpay', refund_method='original_payment_method'.
--        • Removes 'cod_cash_return' as a valid gateway or refund_method.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Schema additions ───────────────────────────────────────────────────────

ALTER TABLE refund_requests
  ADD COLUMN IF NOT EXISTS bank_details_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS bank_details_submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS bank_upi_details           JSONB;

-- ── 2. Column-level security: hide bank_upi_details from anon role ─────────────
--
-- Column-level grants are ADDITIVE, not SUBTRACTIVE (same caveat as migration
-- 000017).  We must first REVOKE the table-level SELECT that Supabase's default
-- privilege scaffold grants to anon, then GRANT only the safe columns back.
--
-- authenticated (admin role) is NOT revoked so admins can still SELECT all
-- columns including bank_upi_details via the admin_all_refund_requests policy.

REVOKE SELECT ON refund_requests FROM anon;

GRANT SELECT (
  id, ticket_number, booking_id, customer_id, payment_id, issue_category_id,
  description, requested_amount, evidence_urls, evidence_count,
  payment_method_snapshot, amount_paid_snapshot,
  status, approved_amount, admin_notes, decision_notes,
  reviewed_by, reviewed_at, processed_amount,
  closed_at, closed_by, created_at, updated_at,
  bank_details_requested_at, bank_details_submitted_at
) ON refund_requests TO anon;

-- ── 3. admin_request_cod_bank_details ────────────────────────────────────────
--
-- Sends a message to the customer asking for bank/UPI details, and records the
-- request timestamp on the ticket.  Only valid for COD/cash bookings that are
-- in an approved/partially_approved/failed state and where the customer has not
-- yet submitted details.  Calling again (re-send) is allowed before submission.

CREATE OR REPLACE FUNCTION admin_request_cod_bank_details(p_request_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_current_status    TEXT;
  v_payment_method    TEXT;
  v_bank_submitted_at TIMESTAMPTZ;
  v_admin_auth_id     UUID := auth.uid();
  v_admin_row_id      UUID;
BEGIN
  PERFORM fn_assert_active_admin();

  SELECT status, payment_method_snapshot, bank_details_submitted_at
    INTO v_current_status, v_payment_method, v_bank_submitted_at
    FROM refund_requests
   WHERE id = p_request_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_payment_method NOT IN ('cod', 'cash') THEN
    RAISE EXCEPTION 'Bank/UPI details can only be requested for COD or cash bookings'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_current_status NOT IN ('approved', 'partially_approved', 'failed') THEN
    RAISE EXCEPTION 'Cannot request bank details from status "%"', v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  IF v_bank_submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Customer has already submitted their bank/UPI details'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT id INTO v_admin_row_id
    FROM admin_users
   WHERE auth_user_id = v_admin_auth_id
   LIMIT 1;

  UPDATE refund_requests
     SET bank_details_requested_at = now(),
         updated_at                = now()
   WHERE id = p_request_id;

  INSERT INTO refund_messages (
    refund_request_id, sender_type, sender_id, message, is_internal
  ) VALUES (
    p_request_id,
    'admin',
    COALESCE(v_admin_row_id, v_admin_auth_id),
    'Your refund has been approved. Since your original payment was Cash on Delivery, '
    'please provide your bank account or UPI details so we can process the transfer. '
    'Open this query and go to the Overview tab to submit your details.',
    false
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_request_cod_bank_details(UUID) TO authenticated;

-- ── 4. customer_submit_bank_upi_details ──────────────────────────────────────
--
-- Customer submits bank account or UPI details for a COD refund.  Stores them
-- in bank_upi_details (admin-only column) and sets bank_details_submitted_at.
-- Sends a confirmation message visible to both customer and admin.
--
-- Expected p_details shapes:
--   Bank: { "type": "bank", "account_holder_name": "…", "account_number": "…",
--           "ifsc_code": "…", "bank_name": "…" (optional) }
--   UPI:  { "type": "upi", "upi_id": "…" }

CREATE OR REPLACE FUNCTION customer_submit_bank_upi_details(
  p_request_id  UUID,
  p_details     JSONB,
  p_customer_id UUID DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_customer_id       UUID;
  v_payment_method    TEXT;
  v_bank_requested_at TIMESTAMPTZ;
  v_bank_submitted_at TIMESTAMPTZ;
  v_detail_type       TEXT;
BEGIN
  -- Resolve customer identity (same dual-mode pattern as other customer RPCs).
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_customer_id
      FROM customers
     WHERE auth_user_id = auth.uid() AND is_active = TRUE
     LIMIT 1;
  ELSIF p_customer_id IS NOT NULL THEN
    SELECT id INTO v_customer_id
      FROM customers
     WHERE id = p_customer_id AND is_active = TRUE
     LIMIT 1;
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated customer not found'
      USING ERRCODE = '42501';
  END IF;

  IF p_details IS NULL OR p_details = '{}'::JSONB THEN
    RAISE EXCEPTION 'Bank/UPI details cannot be empty'
      USING ERRCODE = 'P0001';
  END IF;

  v_detail_type := p_details ->> 'type';
  IF v_detail_type NOT IN ('bank', 'upi') THEN
    RAISE EXCEPTION 'Details type must be "bank" or "upi" (got: "%")', v_detail_type
      USING ERRCODE = 'P0001';
  END IF;

  IF v_detail_type = 'bank' THEN
    IF (p_details ->> 'account_number') IS NULL OR trim(p_details ->> 'account_number') = '' THEN
      RAISE EXCEPTION 'account_number is required for bank transfers'
        USING ERRCODE = 'P0001';
    END IF;
    IF (p_details ->> 'ifsc_code') IS NULL OR trim(p_details ->> 'ifsc_code') = '' THEN
      RAISE EXCEPTION 'ifsc_code is required for bank transfers'
        USING ERRCODE = 'P0001';
    END IF;
    IF (p_details ->> 'account_holder_name') IS NULL OR trim(p_details ->> 'account_holder_name') = '' THEN
      RAISE EXCEPTION 'account_holder_name is required for bank transfers'
        USING ERRCODE = 'P0001';
    END IF;
  ELSIF v_detail_type = 'upi' THEN
    IF (p_details ->> 'upi_id') IS NULL OR trim(p_details ->> 'upi_id') = '' THEN
      RAISE EXCEPTION 'upi_id is required for UPI transfers'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  SELECT payment_method_snapshot, bank_details_requested_at, bank_details_submitted_at
    INTO v_payment_method, v_bank_requested_at, v_bank_submitted_at
    FROM refund_requests
   WHERE id = p_request_id
     AND customer_id = v_customer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request not found or does not belong to this customer'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_payment_method NOT IN ('cod', 'cash') THEN
    RAISE EXCEPTION 'Bank/UPI details are only required for COD or cash refunds'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_bank_requested_at IS NULL THEN
    RAISE EXCEPTION 'Bank/UPI details have not been requested yet'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_bank_submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Bank/UPI details have already been submitted. Contact support to update them.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE refund_requests
     SET bank_upi_details          = p_details,
         bank_details_submitted_at = now(),
         updated_at                = now()
   WHERE id = p_request_id;

  INSERT INTO refund_messages (
    refund_request_id, sender_type, sender_id, message, is_internal
  ) VALUES (
    p_request_id,
    'customer',
    v_customer_id,
    'I have submitted my bank/UPI transfer details for the refund.',
    false
  );
END;
$$;

GRANT EXECUTE ON FUNCTION customer_submit_bank_upi_details(UUID, JSONB, UUID)
  TO anon, authenticated;

-- ── 5. admin_initiate_refund_transaction (replaces migration 000009) ──────────
--
-- Updated validation:
--   • COD/cash: gateway must be 'manual', refund_method must be 'manual',
--     bank_details_submitted_at must be set (customer submitted details).
--   • Online: gateway must be 'razorpay', refund_method must be
--     'original_payment_method'.
--   • 'cod_cash_return' is no longer a valid gateway or refund_method.
--
-- All other safety guards (balance check, approved-amount cap, duplicate
-- protection via row lock, ticket status transitions) are unchanged.

CREATE OR REPLACE FUNCTION admin_initiate_refund_transaction(
  p_request_id    UUID,
  p_amount        NUMERIC,
  p_gateway       TEXT,
  p_refund_method TEXT,
  p_notes         TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_current_status    TEXT;
  v_approved_amount   NUMERIC;
  v_amount_paid       NUMERIC;
  v_payment_method    TEXT;
  v_bank_submitted_at TIMESTAMPTZ;
  v_already_completed NUMERIC;
  v_remaining         NUMERIC;
  v_txn_id            UUID;
  v_admin_auth_id     UUID := auth.uid();
BEGIN
  PERFORM fn_assert_active_admin();

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Transaction amount must be greater than zero'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_gateway NOT IN ('razorpay', 'manual') THEN
    RAISE EXCEPTION 'Invalid gateway "%". Allowed values: razorpay, manual.', p_gateway
      USING ERRCODE = 'P0001';
  END IF;

  IF p_refund_method NOT IN ('original_payment_method', 'manual') THEN
    RAISE EXCEPTION 'Invalid refund_method "%". Allowed values: original_payment_method, manual.', p_refund_method
      USING ERRCODE = 'P0001';
  END IF;

  -- Lock the ticket row to prevent concurrent over-refund.
  SELECT status, approved_amount, amount_paid_snapshot,
         payment_method_snapshot, bank_details_submitted_at
    INTO v_current_status, v_approved_amount, v_amount_paid,
         v_payment_method, v_bank_submitted_at
    FROM refund_requests
   WHERE id = p_request_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_current_status NOT IN ('approved', 'partially_approved', 'failed') THEN
    RAISE EXCEPTION
      'Cannot initiate a refund transaction from status "%". '
      'Ticket must be approved or partially_approved first.',
      v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  -- Payment-type specific gateway and method enforcement
  IF v_payment_method IN ('cod', 'cash') THEN
    IF p_gateway <> 'manual' THEN
      RAISE EXCEPTION
        'COD/cash refunds must use the manual gateway (submitted: "%")', p_gateway
        USING ERRCODE = 'P0001';
    END IF;
    IF p_refund_method <> 'manual' THEN
      RAISE EXCEPTION
        'COD/cash refunds must use the manual refund method (submitted: "%")', p_refund_method
        USING ERRCODE = 'P0001';
    END IF;
    IF v_bank_submitted_at IS NULL THEN
      RAISE EXCEPTION
        'Cannot initiate a COD/cash refund until the customer has submitted their bank/UPI details'
        USING ERRCODE = 'P0001';
    END IF;
  ELSIF v_payment_method = 'online' THEN
    IF p_gateway <> 'razorpay' THEN
      RAISE EXCEPTION
        'Online payment refunds must use the razorpay gateway (submitted: "%")', p_gateway
        USING ERRCODE = 'P0001';
    END IF;
    IF p_refund_method <> 'original_payment_method' THEN
      RAISE EXCEPTION
        'Online payment refunds must refund to the original payment method (submitted: "%")', p_refund_method
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Compute remaining refundable balance (under the row lock).
  SELECT COALESCE(SUM(amount), 0) INTO v_already_completed
    FROM refund_transactions
   WHERE refund_request_id = p_request_id
     AND status = 'completed';

  v_remaining := GREATEST(0, v_amount_paid - v_already_completed);

  IF p_amount > v_remaining THEN
    RAISE EXCEPTION
      'Transaction amount (%) exceeds remaining refundable balance (%)',
      p_amount, v_remaining
      USING ERRCODE = 'P0001';
  END IF;

  IF v_approved_amount IS NOT NULL
     AND p_amount > (v_approved_amount - v_already_completed) THEN
    RAISE EXCEPTION
      'Transaction amount (%) exceeds remaining approved amount (%)',
      p_amount, (v_approved_amount - v_already_completed)
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO refund_transactions (
    refund_request_id, amount, gateway, refund_method, initiated_by, metadata
  ) VALUES (
    p_request_id, p_amount, p_gateway, p_refund_method, v_admin_auth_id,
    CASE WHEN p_notes IS NOT NULL
         THEN jsonb_build_object('notes', p_notes)
         ELSE '{}'::jsonb
    END
  )
  RETURNING id INTO v_txn_id;

  UPDATE refund_requests
     SET status     = 'processing',
         updated_at = now()
   WHERE id = p_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type, notes, metadata
  ) VALUES (
    p_request_id, v_current_status, 'processing',
    v_admin_auth_id, 'admin', p_notes,
    jsonb_build_object(
      'transaction_id', v_txn_id,
      'amount',         p_amount,
      'gateway',        p_gateway
    )
  );

  RETURN v_txn_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_initiate_refund_transaction(UUID, NUMERIC, TEXT, TEXT, TEXT)
  TO authenticated;
