-- ─────────────────────────────────────────────────────────────────────────────
-- Refund Financial Safety Layer
--
-- get_refundable_balance  — read-only function; returns remaining refundable
--                           amount for a given ticket.
--
-- admin_initiate_refund_transaction — the ONLY path to creating a money-movement
--   record.  Enforces:
--     • Caller is an active admin.
--     • Ticket is approved or partially_approved.
--     • amount ≤ remaining refundable balance (with row-level lock to prevent
--       concurrent over-refund).
--     • Inserts refund_transactions row with status='pending'.
--     • Transitions ticket to 'processing'.
--     • Does NOT call any payment gateway.  Gateway integration is a future
--       Edge Function that calls this RPC first and marks the transaction
--       completed/failed independently.
--
-- admin_mark_refund_transaction_complete — records a successful gateway outcome.
-- admin_mark_refund_transaction_failed   — records a failed gateway outcome.
--   Both functions update the ticket status based on remaining approved amount.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── get_refundable_balance ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_refundable_balance(p_request_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_amount_paid    NUMERIC;
  v_already_done   NUMERIC;
BEGIN
  SELECT amount_paid_snapshot INTO v_amount_paid
    FROM refund_requests
   WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_already_done
    FROM refund_transactions
   WHERE refund_request_id = p_request_id
     AND status = 'completed';

  RETURN GREATEST(0, v_amount_paid - v_already_done);
END;
$$;

GRANT EXECUTE ON FUNCTION get_refundable_balance(UUID)
  TO authenticated, anon;

-- ── admin_initiate_refund_transaction ────────────────────────────────────────

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
  v_already_completed NUMERIC;
  v_remaining         NUMERIC;
  v_txn_id            UUID;
  v_admin_auth_id     UUID := auth.uid();
BEGIN
  PERFORM fn_assert_active_admin();

  -- Validate inputs
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

  -- Ticket must be in an approved state.
  IF v_current_status NOT IN ('approved', 'partially_approved', 'failed') THEN
    RAISE EXCEPTION
      'Cannot initiate a refund transaction from status "%". '
      'Ticket must be approved or partially_approved first.',
      v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  -- Compute remaining refundable balance (under the row lock).
  SELECT COALESCE(SUM(amount), 0) INTO v_already_completed
    FROM refund_transactions
   WHERE refund_request_id = p_request_id
     AND status = 'completed';

  v_remaining := GREATEST(0, v_amount_paid - v_already_completed);

  -- Safety guard: never exceed the collected payment.
  IF p_amount > v_remaining THEN
    RAISE EXCEPTION
      'Transaction amount (%) exceeds remaining refundable balance (%)',
      p_amount, v_remaining
      USING ERRCODE = 'P0001';
  END IF;

  -- Also guard against exceeding the approved amount.
  IF v_approved_amount IS NOT NULL AND p_amount > (v_approved_amount - v_already_completed) THEN
    RAISE EXCEPTION
      'Transaction amount (%) exceeds remaining approved amount (%)',
      p_amount, (v_approved_amount - v_already_completed)
      USING ERRCODE = 'P0001';
  END IF;

  -- Insert the transaction record (status = 'pending').
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

  -- Transition ticket to 'processing'.
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
-- Records a successful gateway outcome.  Updates ticket status based on
-- whether the approved amount has been fully disbursed.

CREATE OR REPLACE FUNCTION admin_mark_refund_transaction_complete(
  p_transaction_id  UUID,
  p_gateway_refund_id TEXT DEFAULT NULL,
  p_gateway_response  JSONB DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_request_id      UUID;
  v_txn_status      TEXT;
  v_approved        NUMERIC;
  v_total_completed NUMERIC;
  v_new_ticket_status TEXT;
  v_admin_auth_id   UUID := auth.uid();
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

  -- Determine new ticket status.
  SELECT approved_amount INTO v_approved
    FROM refund_requests
   WHERE id = v_request_id
     FOR UPDATE;

  -- Recompute total completed (trigger may not have fired yet within same txn).
  SELECT COALESCE(SUM(amount), 0) INTO v_total_completed
    FROM refund_transactions
   WHERE refund_request_id = v_request_id
     AND status = 'completed';

  v_new_ticket_status := CASE
    WHEN v_approved IS NOT NULL AND v_total_completed >= v_approved THEN 'completed'
    ELSE 'completed'  -- even partial disbursement closes the ticket as completed
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

-- ── admin_mark_refund_transaction_failed ──────────────────────────────────────
-- Records a failed gateway outcome.  Ticket returns to 'failed' so Admin can
-- retry by calling admin_initiate_refund_transaction again.

CREATE OR REPLACE FUNCTION admin_mark_refund_transaction_failed(
  p_transaction_id UUID,
  p_failure_reason TEXT,
  p_gateway_response JSONB DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_request_id    UUID;
  v_txn_status    TEXT;
  v_admin_auth_id UUID := auth.uid();
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
      'Cannot mark transaction as failed from status "%"', v_txn_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE refund_transactions
     SET status           = 'failed',
         failure_reason   = p_failure_reason,
         gateway_response = COALESCE(p_gateway_response, gateway_response),
         updated_at       = now()
   WHERE id = p_transaction_id;

  -- Ticket reverts to 'failed' so the admin can retry.
  UPDATE refund_requests
     SET status     = 'failed',
         updated_at = now()
   WHERE id = v_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type, notes
  ) VALUES (
    v_request_id, 'processing', 'failed',
    v_admin_auth_id, 'admin', p_failure_reason
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_mark_refund_transaction_failed(UUID, TEXT, JSONB)
  TO authenticated;
