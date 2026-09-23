-- ─────────────────────────────────────────────────────────────────────────────
-- admin_begin_razorpay_refund_processing
--
-- Called by the process-razorpay-refund Edge Function at the START of a gateway
-- API call.  The function atomically:
--   1. Verifies the caller is an active admin (fn_assert_active_admin via auth.uid()).
--   2. Locks the refund_transactions row FOR UPDATE (blocks concurrent Edge Function
--      calls for the same transaction).
--   3. Validates the transaction is in 'pending' state with gateway = 'razorpay'.
--      Returns an error for 'processing' (already in-flight — check Razorpay
--      dashboard) or any other non-pending state.
--   4. Transitions the transaction from 'pending' to 'processing'.
--   5. Returns a JSONB payload with all data the Edge Function needs to call
--      the Razorpay Refunds API:
--        transaction_id    — the UUID passed in (echo for correlation)
--        refund_request_id — the parent ticket's ID
--        amount_paise      — refund amount converted to paise (integer)
--        gateway_payment_id — the Razorpay pay_XXXXX from booking_payments
--
-- SECURITY: SECURITY DEFINER so it can lock and mutate refund_transactions
-- even though the Edge Function runs as the authenticated user.  The caller
-- identity (admin user) is verified through fn_assert_active_admin() which uses
-- auth.uid() — the JWT-derived user ID injected by Supabase auth.
--
-- The Edge Function calls admin_mark_refund_transaction_complete or
-- admin_mark_refund_transaction_failed (existing RPCs) after the Razorpay API
-- call returns.  All three functions together form the atomic safety boundary.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_begin_razorpay_refund_processing(
  p_transaction_id UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_txn_status        TEXT;
  v_txn_gateway       TEXT;
  v_refund_request_id UUID;
  v_amount            NUMERIC;
  v_payment_id        UUID;
  v_gateway_payment_id TEXT;
BEGIN
  PERFORM fn_assert_active_admin();

  -- Lock the transaction row.  Prevents concurrent Edge Function invocations
  -- for the same transaction from both proceeding to the Razorpay API.
  SELECT rt.status, rt.gateway, rt.refund_request_id, rt.amount
    INTO v_txn_status, v_txn_gateway, v_refund_request_id, v_amount
    FROM refund_transactions rt
   WHERE rt.id = p_transaction_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund transaction % not found', p_transaction_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Only 'razorpay' gateway transactions are routed through this function.
  IF v_txn_gateway <> 'razorpay' THEN
    RAISE EXCEPTION
      'Transaction % uses gateway "%" — only razorpay transactions can be '
      'processed via this function.',
      p_transaction_id, v_txn_gateway
      USING ERRCODE = 'P0001';
  END IF;

  -- Only 'pending' transactions may be initiated.
  -- 'processing' means an Edge Function call is already in-flight.
  -- Reject to prevent a second concurrent Razorpay API call.
  IF v_txn_status = 'processing' THEN
    RAISE EXCEPTION
      'Transaction % is already in processing state. A Razorpay API call may '
      'be in-flight. Check the Razorpay dashboard and mark the transaction '
      'complete or failed manually.',
      p_transaction_id
      USING ERRCODE = 'P0001';
  END IF;

  IF v_txn_status <> 'pending' THEN
    RAISE EXCEPTION
      'Cannot begin Razorpay processing from status "%". '
      'Only pending transactions can be processed.',
      v_txn_status
      USING ERRCODE = 'P0001';
  END IF;

  -- Retrieve payment_id from the parent ticket.
  SELECT rr.payment_id
    INTO v_payment_id
    FROM refund_requests rr
   WHERE rr.id = v_refund_request_id;

  IF v_payment_id IS NULL THEN
    RAISE EXCEPTION
      'Refund request % has no associated booking_payments row. '
      'Cannot initiate a Razorpay refund without an original online payment.',
      v_refund_request_id
      USING ERRCODE = 'P0001';
  END IF;

  -- Retrieve the Razorpay payment ID (pay_XXXXX) from booking_payments.
  SELECT bp.gateway_payment_id
    INTO v_gateway_payment_id
    FROM booking_payments bp
   WHERE bp.id = v_payment_id;

  IF v_gateway_payment_id IS NULL THEN
    RAISE EXCEPTION
      'booking_payments row % has no gateway_payment_id. '
      'The original payment may not have been captured by Razorpay yet.',
      v_payment_id
      USING ERRCODE = 'P0001';
  END IF;

  -- Atomically transition pending → processing.
  UPDATE refund_transactions
     SET status     = 'processing',
         updated_at = now()
   WHERE id = p_transaction_id;

  -- Return everything the Edge Function needs to call the Razorpay Refunds API.
  RETURN jsonb_build_object(
    'transaction_id',    p_transaction_id,
    'refund_request_id', v_refund_request_id,
    'amount_paise',      (ROUND(v_amount * 100))::BIGINT,
    'gateway_payment_id', v_gateway_payment_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_begin_razorpay_refund_processing(UUID)
  TO authenticated;
