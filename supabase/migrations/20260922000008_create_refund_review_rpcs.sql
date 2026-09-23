-- ─────────────────────────────────────────────────────────────────────────────
-- Admin Refund Review RPCs
--
-- All four functions share the same safety pattern:
--   1. Validate the calling user is an active admin.
--   2. Lock the refund_requests row FOR UPDATE.
--   3. Validate the current status allows the requested transition.
--   4. Mutate the row and insert a refund_status_history entry atomically.
--
-- None of these functions touch money.  Financial movement is handled
-- exclusively by admin_initiate_refund_transaction (migration 20260922000009).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Helper: assert caller is an active admin ──────────────────────────────────
-- Called at the top of every review RPC.

CREATE OR REPLACE FUNCTION fn_assert_active_admin()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
     WHERE auth_user_id = auth.uid()
       AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Not authorised: caller is not an active admin'
      USING ERRCODE = '42501';
  END IF;
END;
$$;

-- ── 1. admin_mark_refund_under_review ────────────────────────────────────────
-- Transitions: submitted → under_review
--              more_info_requested → under_review  (admin resumed review)

CREATE OR REPLACE FUNCTION admin_mark_refund_under_review(
  p_request_id UUID
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_current_status TEXT;
  v_admin_auth_id  UUID := auth.uid();
BEGIN
  PERFORM fn_assert_active_admin();

  SELECT status INTO v_current_status
    FROM refund_requests
   WHERE id = p_request_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_current_status NOT IN ('submitted', 'more_info_requested') THEN
    RAISE EXCEPTION
      'Cannot move to under_review from status "%"', v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE refund_requests
     SET status     = 'under_review',
         updated_at = now()
   WHERE id = p_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type
  ) VALUES (
    p_request_id, v_current_status, 'under_review',
    v_admin_auth_id, 'admin'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_mark_refund_under_review(UUID) TO authenticated;

-- ── 2. admin_request_more_info_refund ────────────────────────────────────────
-- Transitions: submitted → more_info_requested
--              under_review → more_info_requested
-- Also posts an admin message on the ticket thread.

CREATE OR REPLACE FUNCTION admin_request_more_info_refund(
  p_request_id UUID,
  p_message    TEXT
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_current_status TEXT;
  v_admin_auth_id  UUID := auth.uid();
  v_admin_row_id   UUID;
BEGIN
  PERFORM fn_assert_active_admin();

  IF p_message IS NULL OR length(trim(p_message)) = 0 THEN
    RAISE EXCEPTION 'A message is required when requesting more information'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT status INTO v_current_status
    FROM refund_requests
   WHERE id = p_request_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_current_status NOT IN ('submitted', 'under_review') THEN
    RAISE EXCEPTION
      'Cannot request more info from status "%"', v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  -- Resolve the admin_users.id for the message sender_id column.
  SELECT id INTO v_admin_row_id
    FROM admin_users
   WHERE auth_user_id = v_admin_auth_id
   LIMIT 1;

  UPDATE refund_requests
     SET status     = 'more_info_requested',
         updated_at = now()
   WHERE id = p_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type, notes
  ) VALUES (
    p_request_id, v_current_status, 'more_info_requested',
    v_admin_auth_id, 'admin', p_message
  );

  INSERT INTO refund_messages (
    refund_request_id, sender_type, sender_id, message, is_internal
  ) VALUES (
    p_request_id, 'admin', COALESCE(v_admin_row_id, v_admin_auth_id),
    p_message, false
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_request_more_info_refund(UUID, TEXT) TO authenticated;

-- ── 3. admin_approve_refund_request ──────────────────────────────────────────
-- Transitions: under_review → approved / partially_approved
--              submitted → approved / partially_approved (direct approval)
--
-- approved_amount MUST be > 0 and ≤ amount_paid_snapshot.
-- If approved_amount = requested_amount → approved.
-- If approved_amount < requested_amount → partially_approved.
--
-- This function does NOT initiate money movement.

CREATE OR REPLACE FUNCTION admin_approve_refund_request(
  p_request_id      UUID,
  p_approved_amount NUMERIC,
  p_notes           TEXT DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_current_status  TEXT;
  v_requested       NUMERIC;
  v_amount_paid     NUMERIC;
  v_new_status      TEXT;
  v_admin_auth_id   UUID := auth.uid();
BEGIN
  PERFORM fn_assert_active_admin();

  IF p_approved_amount IS NULL OR p_approved_amount <= 0 THEN
    RAISE EXCEPTION 'Approved amount must be greater than zero'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT status, requested_amount, amount_paid_snapshot
    INTO v_current_status, v_requested, v_amount_paid
    FROM refund_requests
   WHERE id = p_request_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_current_status NOT IN ('submitted', 'under_review', 'more_info_requested') THEN
    RAISE EXCEPTION
      'Cannot approve from status "%"', v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  -- Financial safety: approved amount cannot exceed what was actually collected.
  IF p_approved_amount > v_amount_paid THEN
    RAISE EXCEPTION
      'Approved amount (%) exceeds the collected payment amount (%)',
      p_approved_amount, v_amount_paid
      USING ERRCODE = 'P0001';
  END IF;

  v_new_status := CASE
    WHEN p_approved_amount >= v_requested THEN 'approved'
    ELSE 'partially_approved'
  END;

  UPDATE refund_requests
     SET status          = v_new_status,
         approved_amount = p_approved_amount,
         admin_notes     = COALESCE(p_notes, admin_notes),
         decision_notes  = p_notes,
         reviewed_by     = v_admin_auth_id,
         reviewed_at     = now(),
         updated_at      = now()
   WHERE id = p_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type, notes,
    metadata
  ) VALUES (
    p_request_id, v_current_status, v_new_status,
    v_admin_auth_id, 'admin', p_notes,
    jsonb_build_object('approved_amount', p_approved_amount)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_approve_refund_request(UUID, NUMERIC, TEXT)
  TO authenticated;

-- ── 4. admin_reject_refund_request ───────────────────────────────────────────
-- Transitions: submitted / under_review / more_info_requested → rejected

CREATE OR REPLACE FUNCTION admin_reject_refund_request(
  p_request_id UUID,
  p_reason     TEXT
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_current_status TEXT;
  v_admin_auth_id  UUID := auth.uid();
BEGIN
  PERFORM fn_assert_active_admin();

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'A rejection reason is required'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT status INTO v_current_status
    FROM refund_requests
   WHERE id = p_request_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_current_status NOT IN ('submitted', 'under_review', 'more_info_requested') THEN
    RAISE EXCEPTION
      'Cannot reject from status "%"', v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE refund_requests
     SET status         = 'rejected',
         decision_notes = p_reason,
         reviewed_by    = v_admin_auth_id,
         reviewed_at    = now(),
         updated_at     = now()
   WHERE id = p_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type, notes
  ) VALUES (
    p_request_id, v_current_status, 'rejected',
    v_admin_auth_id, 'admin', p_reason
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_reject_refund_request(UUID, TEXT) TO authenticated;

-- ── 5. admin_close_refund_request ────────────────────────────────────────────
-- Transitions: any non-processing/non-pending status → closed

CREATE OR REPLACE FUNCTION admin_close_refund_request(
  p_request_id UUID,
  p_notes      TEXT DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_current_status TEXT;
  v_admin_auth_id  UUID := auth.uid();
BEGIN
  PERFORM fn_assert_active_admin();

  SELECT status INTO v_current_status
    FROM refund_requests
   WHERE id = p_request_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Cannot close a ticket while a transaction is actively processing.
  IF v_current_status = 'processing' THEN
    RAISE EXCEPTION
      'Cannot close a ticket while a refund transaction is in progress'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_current_status = 'closed' THEN
    RETURN;  -- idempotent
  END IF;

  UPDATE refund_requests
     SET status     = 'closed',
         closed_at  = now(),
         closed_by  = v_admin_auth_id,
         updated_at = now()
   WHERE id = p_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type, notes
  ) VALUES (
    p_request_id, v_current_status, 'closed',
    v_admin_auth_id, 'admin', p_notes
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_close_refund_request(UUID, TEXT) TO authenticated;
