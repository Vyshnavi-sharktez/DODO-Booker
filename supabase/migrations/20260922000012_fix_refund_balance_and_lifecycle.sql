-- ─────────────────────────────────────────────────────────────────────────────
-- Fix refund balance calculation and partial-refund ticket lifecycle
--
-- Bug 1 — get_refundable_balance and admin_initiate_refund_transaction both
--   computed remaining balance as (amount_paid_snapshot - completed_only).
--   Two defects:
--   (a) approved_amount was ignored, causing the balance to show ₹500 when
--       only ₹400 was approved (display misleads admin; RPC would reject the
--       excess server-side, but the UI showed the wrong ceiling).
--   (b) Pending/processing transactions were not subtracted, so the balance
--       could show uncommitted in-flight amounts as refundable.
--
--   Fix: effective_limit = LEAST(amount_paid_snapshot,
--                                COALESCE(approved_amount, amount_paid_snapshot))
--        already_used    = SUM(completed + pending + processing transactions)
--        remaining       = GREATEST(0, effective_limit - already_used)
--
-- Bug 2 — admin_mark_refund_transaction_complete had both CASE branches
--   returning 'completed', permanently locking a ticket after any transaction
--   regardless of how much approved amount had actually been disbursed.
--
--   Fix: transition to 'completed' only when total_completed >= effective
--   approved ceiling; otherwise return ticket to 'approved' (full-amount
--   approval) or 'partially_approved' (partial approval) so that further
--   transactions can be initiated until the full approved amount is disbursed.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── get_refundable_balance ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_refundable_balance(p_request_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_amount_paid     NUMERIC;
  v_approved_amount NUMERIC;
  v_effective_limit NUMERIC;
  v_already_used    NUMERIC;
BEGIN
  SELECT amount_paid_snapshot, approved_amount
    INTO v_amount_paid, v_approved_amount
    FROM refund_requests
   WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Effective ceiling: approved_amount caps the refundable limit when set.
  v_effective_limit := LEAST(
    v_amount_paid,
    COALESCE(v_approved_amount, v_amount_paid)
  );

  -- Count completed, pending, and processing transactions.
  -- In-flight amounts are included so the display reflects what is actually
  -- initiatable, preventing the UI from showing already-committed funds as free.
  SELECT COALESCE(SUM(amount), 0)
    INTO v_already_used
    FROM refund_transactions
   WHERE refund_request_id = p_request_id
     AND status IN ('completed', 'pending', 'processing');

  RETURN GREATEST(0, v_effective_limit - v_already_used);
END;
$$;

GRANT EXECUTE ON FUNCTION get_refundable_balance(UUID)
  TO authenticated, anon;

-- ── admin_initiate_refund_transaction ────────────────────────────────────────
--
-- Key changes from the previous version:
--   • Single unified remaining-balance check replacing two separate guards.
--   • effective_limit = LEAST(amount_paid, COALESCE(approved_amount, amount_paid))
--   • already_used counts completed + pending + processing (not completed-only).
--   • SELECT FOR UPDATE row lock is preserved.
--   • fn_assert_active_admin() call is preserved.

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
  v_effective_limit   NUMERIC;
  v_already_used      NUMERIC;
  v_remaining         NUMERIC;
  v_txn_id            UUID;
  v_admin_auth_id     UUID := auth.uid();
BEGIN
  PERFORM fn_assert_active_admin();

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Transaction amount must be greater than zero'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_gateway NOT IN ('razorpay', 'manual', 'cod_cash_return') THEN
    RAISE EXCEPTION 'Invalid gateway "%"', p_gateway
      USING ERRCODE = 'P0001';
  END IF;

  IF p_refund_method NOT IN (
    'original_payment_method', 'manual', 'cod_cash_return'
  ) THEN
    RAISE EXCEPTION 'Invalid refund_method "%"', p_refund_method
      USING ERRCODE = 'P0001';
  END IF;

  -- Lock the ticket row to prevent concurrent over-refund.
  SELECT status, approved_amount, amount_paid_snapshot
    INTO v_current_status, v_approved_amount, v_amount_paid
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

  -- Effective ceiling: approved_amount caps the limit when set.
  v_effective_limit := LEAST(
    v_amount_paid,
    COALESCE(v_approved_amount, v_amount_paid)
  );

  -- Count completed + in-flight (pending/processing) under the row lock.
  -- Including in-flight amounts prevents concurrent over-initiation even when
  -- the ticket FSM has returned to an initiatable state after partial completion.
  SELECT COALESCE(SUM(amount), 0) INTO v_already_used
    FROM refund_transactions
   WHERE refund_request_id = p_request_id
     AND status IN ('completed', 'pending', 'processing');

  v_remaining := GREATEST(0, v_effective_limit - v_already_used);

  IF p_amount > v_remaining THEN
    RAISE EXCEPTION
      'Transaction amount (%) exceeds remaining refundable balance (%). '
      'Approved/paid ceiling: %, already accounted: %.',
      p_amount, v_remaining, v_effective_limit, v_already_used
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO refund_transactions (
    refund_request_id,
    amount,
    gateway,
    refund_method,
    initiated_by,
    metadata
  ) VALUES (
    p_request_id,
    p_amount,
    p_gateway,
    p_refund_method,
    v_admin_auth_id,
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
    changed_by, changed_by_type, notes,
    metadata
  ) VALUES (
    p_request_id, v_current_status, 'processing',
    v_admin_auth_id, 'admin', p_notes,
    jsonb_build_object(
      'transaction_id', v_txn_id,
      'amount', p_amount,
      'gateway', p_gateway
    )
  );

  RETURN v_txn_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_initiate_refund_transaction(UUID, NUMERIC, TEXT, TEXT, TEXT)
  TO authenticated;

-- ── admin_mark_refund_transaction_complete ────────────────────────────────────
--
-- Key changes from the previous version:
--   • Also fetches amount_paid_snapshot (needed for approval classification).
--   • CASE statement fixed: ELSE branch returns 'approved' or 'partially_approved'
--     rather than 'completed', so the ticket remains initiatable after partial
--     disbursement.  Ticket only reaches 'completed' when total_completed
--     >= COALESCE(approved_amount, amount_paid_snapshot).
--   • Approval classification: 'partially_approved' when approved_amount is set
--     and is less than amount_paid_snapshot (the approval was for less than the
--     full collected amount); 'approved' otherwise.

CREATE OR REPLACE FUNCTION admin_mark_refund_transaction_complete(
  p_transaction_id    UUID,
  p_gateway_refund_id TEXT DEFAULT NULL,
  p_gateway_response  JSONB DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_request_id        UUID;
  v_txn_status        TEXT;
  v_approved          NUMERIC;
  v_amount_paid       NUMERIC;
  v_total_completed   NUMERIC;
  v_new_ticket_status TEXT;
  v_admin_auth_id     UUID := auth.uid();
BEGIN
  PERFORM fn_assert_active_admin();

  SELECT refund_request_id, status
    INTO v_request_id, v_txn_status
    FROM refund_transactions
   WHERE id = p_transaction_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund transaction % not found', p_transaction_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_txn_status NOT IN ('pending', 'processing') THEN
    RAISE EXCEPTION
      'Cannot mark transaction as complete from status "%"', v_txn_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE refund_transactions
     SET status              = 'completed',
         gateway_refund_id   = p_gateway_refund_id,
         gateway_response    = COALESCE(p_gateway_response, gateway_response),
         completed_at        = now(),
         updated_at          = now()
   WHERE id = p_transaction_id;

  -- Fetch approval context (also locks ticket row).
  SELECT approved_amount, amount_paid_snapshot
    INTO v_approved, v_amount_paid
    FROM refund_requests
   WHERE id = v_request_id
     FOR UPDATE;

  -- Recompute total completed (trigger may not have fired yet within same txn).
  SELECT COALESCE(SUM(amount), 0) INTO v_total_completed
    FROM refund_transactions
   WHERE refund_request_id = v_request_id
     AND status = 'completed';

  -- Determine new ticket status:
  --   'completed'          — all of the approved (or paid, when no limit) amount
  --                          has been disbursed; no further transactions needed.
  --   'partially_approved' — approved_amount was less than amount_paid_snapshot
  --                          and the approved ceiling has not yet been reached.
  --   'approved'           — full-amount approval; ceiling not yet reached.
  v_new_ticket_status := CASE
    WHEN v_total_completed >= COALESCE(v_approved, v_amount_paid)
      THEN 'completed'
    WHEN v_approved IS NOT NULL AND v_approved < v_amount_paid
      THEN 'partially_approved'
    ELSE
      'approved'
  END;

  UPDATE refund_requests
     SET status     = v_new_ticket_status,
         updated_at = now()
   WHERE id = v_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type,
    metadata
  ) VALUES (
    v_request_id, 'processing', v_new_ticket_status,
    v_admin_auth_id, 'admin',
    jsonb_build_object(
      'transaction_id',    p_transaction_id,
      'gateway_refund_id', p_gateway_refund_id,
      'total_completed',   v_total_completed
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_mark_refund_transaction_complete(UUID, TEXT, JSONB)
  TO authenticated;
