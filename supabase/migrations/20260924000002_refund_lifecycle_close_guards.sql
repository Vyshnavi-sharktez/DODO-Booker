-- ─────────────────────────────────────────────────────────────────────────────
-- Refund lifecycle close guards
--
-- Fixes four gaps in the refund ticket lifecycle:
--
-- 1. admin_close_refund_request
--    Previous: allowed closure from ANY non-processing status, including
--    'approved' and 'partially_approved' — admin could close a ticket before
--    the refund was ever processed.
--    Fix: block closure from 'approved' and 'partially_approved'.  Admin must
--    process the refund first (or reject the ticket if the refund is not needed).
--
-- 2. admin_mark_refund_transaction_complete
--    Previous: did not set closed_at on the refund_requests row, even when
--    transitioning to 'completed' (immediately-settled Razorpay refund).
--    Fix: set closed_at = now() when the ticket reaches 'completed'.
--
-- 3. webhook_complete_refund_transaction
--    Previous: same omission — Razorpay webhook confirmation did not set
--    closed_at.  Tickets reached 'completed' without a closure timestamp.
--    Fix: set closed_at = now() when the ticket reaches 'completed'.
--
-- 4. admin_initiate_cod_refund
--    Previous: set status = 'completed' but not closed_at.  COD refunds
--    confirmed by admin had no closure timestamp.
--    Fix: set closed_at = now() atomically with the status = 'completed' update.
--
-- No new columns are added.  closed_at already exists on refund_requests and
-- is set by admin_close_refund_request; this migration extends that behaviour
-- to the three confirmed-success paths.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. admin_close_refund_request — block premature closure ──────────────────

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

  -- Idempotent: already closed — nothing to do.
  IF v_current_status = 'closed' THEN
    RETURN;
  END IF;

  -- Cannot close while a refund transaction is actively in-flight.
  IF v_current_status = 'processing' THEN
    RAISE EXCEPTION
      'Cannot close a ticket while a refund transaction is in progress. '
      'Wait for the Razorpay webhook to confirm or fail the transaction first.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Cannot close while the refund has been approved but not yet processed.
  -- Admin must initiate and complete the Razorpay/COD refund first.  If the
  -- refund is no longer required, reject the request before closing.
  IF v_current_status IN ('approved', 'partially_approved') THEN
    RAISE EXCEPTION
      'Cannot close a ticket in "%" status. '
      'The approved refund must be processed before closing, '
      'or the request must be rejected if the refund is no longer needed.',
      v_current_status
      USING ERRCODE = 'P0001';
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

-- ── 2. admin_mark_refund_transaction_complete — set closed_at on completion ──
--
-- Handles immediately-settled Razorpay refunds (status = "processed" from the
-- Razorpay API).  When the ticket reaches 'completed', the refund is confirmed;
-- set closed_at to record the authoritative closure timestamp.

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

  SELECT approved_amount, amount_paid_snapshot
    INTO v_approved, v_amount_paid
    FROM refund_requests
   WHERE id = v_request_id
     FOR UPDATE;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_completed
    FROM refund_transactions
   WHERE refund_request_id = v_request_id
     AND status = 'completed';

  v_new_ticket_status := CASE
    WHEN v_total_completed >= COALESCE(v_approved, v_amount_paid)
      THEN 'completed'
    WHEN v_approved IS NOT NULL AND v_approved < v_amount_paid
      THEN 'partially_approved'
    ELSE
      'approved'
  END;

  -- Set closed_at when the ticket is confirmed as fully refunded.
  -- This is the authoritative timestamp for confirmed Razorpay refund success.
  UPDATE refund_requests
     SET status     = v_new_ticket_status,
         closed_at  = CASE WHEN v_new_ticket_status = 'completed'
                           THEN now()
                           ELSE closed_at
                      END,
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

-- ── 3. webhook_complete_refund_transaction — set closed_at on completion ─────
--
-- Handles normal-speed Razorpay refunds confirmed by the refund.processed
-- webhook (typically 5–7 business days after initiation).  When the ticket
-- reaches 'completed', set closed_at to record the authoritative closure
-- timestamp from the webhook confirmation.

CREATE OR REPLACE FUNCTION webhook_complete_refund_transaction(
  p_transaction_id    UUID,
  p_gateway_refund_id TEXT,
  p_gateway_response  JSONB DEFAULT NULL
)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_txn_status            TEXT;
  v_txn_gateway_refund_id TEXT;
  v_request_id            UUID;
  v_ticket_from_status    TEXT;
  v_approved              NUMERIC;
  v_amount_paid           NUMERIC;
  v_total_completed       NUMERIC;
  v_new_ticket_status     TEXT;
BEGIN
  SELECT status, gateway_refund_id, refund_request_id
    INTO v_txn_status, v_txn_gateway_refund_id, v_request_id
    FROM refund_transactions
   WHERE id = p_transaction_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund transaction % not found', p_transaction_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_txn_status = 'completed' THEN
    IF v_txn_gateway_refund_id = p_gateway_refund_id THEN
      RETURN 'already_complete';
    END IF;
    RAISE EXCEPTION
      'Transaction % is already completed with gateway_refund_id %. '
      'Refusing to overwrite with a different refund ID %.',
      p_transaction_id, v_txn_gateway_refund_id, p_gateway_refund_id
      USING ERRCODE = 'P0001';
  END IF;

  IF v_txn_status = 'failed' THEN
    RETURN 'already_failed';
  END IF;

  IF v_txn_status NOT IN ('pending', 'processing') THEN
    RAISE EXCEPTION
      'Cannot complete transaction from unexpected status "%"', v_txn_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE refund_transactions
     SET status            = 'completed',
         gateway_refund_id = p_gateway_refund_id,
         gateway_response  = COALESCE(p_gateway_response, gateway_response),
         completed_at      = now(),
         updated_at        = now()
   WHERE id = p_transaction_id;

  SELECT status, approved_amount, amount_paid_snapshot
    INTO v_ticket_from_status, v_approved, v_amount_paid
    FROM refund_requests
   WHERE id = v_request_id
     FOR UPDATE;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_completed
    FROM refund_transactions
   WHERE refund_request_id = v_request_id
     AND status = 'completed';

  v_new_ticket_status := CASE
    WHEN v_total_completed >= COALESCE(v_approved, v_amount_paid)
      THEN 'completed'
    WHEN v_approved IS NOT NULL AND v_approved < v_amount_paid
      THEN 'partially_approved'
    ELSE
      'approved'
  END;

  -- Set closed_at when the webhook confirms the ticket is fully refunded.
  -- This is the authoritative timestamp for confirmed Razorpay webhook success.
  UPDATE refund_requests
     SET status     = v_new_ticket_status,
         closed_at  = CASE WHEN v_new_ticket_status = 'completed'
                           THEN now()
                           ELSE closed_at
                      END,
         updated_at = now()
   WHERE id = v_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type,
    metadata
  ) VALUES (
    v_request_id,
    v_ticket_from_status,
    v_new_ticket_status,
    NULL,
    'system',
    jsonb_build_object(
      'transaction_id',    p_transaction_id,
      'gateway_refund_id', p_gateway_refund_id,
      'total_completed',   v_total_completed,
      'source',            'razorpay_webhook'
    )
  );

  RETURN 'completed';
END;
$$;

GRANT EXECUTE ON FUNCTION webhook_complete_refund_transaction(UUID, TEXT, JSONB)
  TO service_role;

-- ── 4. admin_initiate_cod_refund — set closed_at on completion ───────────────
--
-- COD refunds are confirmed by the admin clicking "Initiate Refund" (one-step).
-- The admin is affirming they have sent or will send the money.  Set closed_at
-- atomically with the status = 'completed' transition so the ticket is
-- authoritatively closed at the moment the admin records the payment.

CREATE OR REPLACE FUNCTION admin_initiate_cod_refund(p_request_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_current_status    TEXT;
  v_approved_amount   NUMERIC;
  v_amount_paid       NUMERIC;
  v_payment_method    TEXT;
  v_bank_submitted_at TIMESTAMPTZ;
  v_already_done      NUMERIC;
  v_refund_amount     NUMERIC;
  v_txn_id            UUID;
  v_admin_auth_id     UUID := auth.uid();
BEGIN
  PERFORM fn_assert_active_admin();

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

  IF v_payment_method NOT IN ('cod', 'cash') THEN
    RAISE EXCEPTION
      'admin_initiate_cod_refund is only for COD/cash bookings (got: "%")',
      v_payment_method
      USING ERRCODE = 'P0001';
  END IF;

  IF v_current_status NOT IN ('approved', 'partially_approved', 'failed') THEN
    RAISE EXCEPTION
      'Cannot initiate refund from status "%". '
      'Ticket must be approved or partially_approved.',
      v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  IF v_bank_submitted_at IS NULL THEN
    RAISE EXCEPTION
      'Cannot initiate COD refund until the customer has submitted '
      'their bank/UPI details'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM refund_transactions
     WHERE refund_request_id = p_request_id
       AND status IN ('pending', 'processing', 'completed')
  ) THEN
    RAISE EXCEPTION
      'A refund transaction has already been initiated for this request'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_already_done
    FROM refund_transactions
   WHERE refund_request_id = p_request_id
     AND status = 'completed';

  v_refund_amount := GREATEST(
    0,
    LEAST(COALESCE(v_approved_amount, v_amount_paid), v_amount_paid) - v_already_done
  );

  IF v_refund_amount <= 0 THEN
    RAISE EXCEPTION 'No refundable balance remaining'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO refund_transactions (
    refund_request_id, amount, gateway, refund_method,
    initiated_by, status, completed_at, metadata
  ) VALUES (
    p_request_id,
    v_refund_amount,
    'manual',
    'manual',
    v_admin_auth_id,
    'completed',
    now(),
    '{}'::jsonb
  )
  RETURNING id INTO v_txn_id;

  -- Transition ticket to 'completed' and record the closure timestamp.
  -- closed_at records when the admin confirmed the COD payment was sent.
  UPDATE refund_requests
     SET status     = 'completed',
         closed_at  = now(),
         updated_at = now()
   WHERE id = p_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type, metadata
  ) VALUES (
    p_request_id,
    v_current_status,
    'completed',
    v_admin_auth_id,
    'admin',
    jsonb_build_object(
      'transaction_id', v_txn_id,
      'amount',         v_refund_amount,
      'gateway',        'manual'
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_initiate_cod_refund(UUID) TO authenticated;

-- ── 5. Back-fill: set closed_at for existing completed tickets ────────────────
--
-- Any refund_requests row that is already 'completed' but has no closed_at was
-- confirmed before this migration was applied (either via the edge function bug
-- or a legitimate immediate-settlement).  Use updated_at as the proxy timestamp
-- — it was set atomically with the status = 'completed' transition, so it is the
-- closest available approximation of when the refund was confirmed.
--
-- Idempotent: skips rows that already have closed_at set.

DO $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE refund_requests
     SET closed_at  = updated_at,
         updated_at = updated_at  -- preserve the original updated_at
   WHERE status     = 'completed'
     AND closed_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE LOG '[DODO][Refund] Back-filled closed_at for % completed refund_request row(s)', v_count;
END;
$$;
