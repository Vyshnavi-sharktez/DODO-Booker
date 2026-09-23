-- ─────────────────────────────────────────────────────────────────────────────
-- Webhook-callable refund RPCs
--
-- These functions are called ONLY by the razorpay-webhook Edge Function
-- (service_role context) after a verified Razorpay webhook signature.
--
-- They mirror the business logic of admin_mark_refund_transaction_complete and
-- admin_mark_refund_transaction_failed but replace fn_assert_active_admin()
-- with the webhook's HMAC-SHA256 signature check (enforced before the RPC is
-- called).  Granting to service_role (not authenticated) prevents any admin or
-- customer JWT from calling these directly.
--
-- Idempotency guarantees:
--   webhook_complete_refund_transaction:
--     - Already completed with the same gateway_refund_id  → 'already_complete'
--     - Already failed (definitive Edge Function rejection) → 'already_failed'
--       (a late success webhook does not overwrite a definitive failure; the
--       admin should investigate any such anomaly manually)
--     - Completed with a DIFFERENT gateway_refund_id        → EXCEPTION
--
--   webhook_fail_refund_transaction:
--     - Already completed (confirmed success)               → 'already_complete'
--       (a confirmed success is NEVER reverted by a failure event)
--     - Already failed                                      → 'already_failed'
--
-- Status transitions written to refund_status_history use changed_by = NULL
-- and changed_by_type = 'system' (existing enum value).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── webhook_complete_refund_transaction ───────────────────────────────────────

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
  -- ── Lock transaction row ────────────────────────────────────────────────────
  SELECT status, gateway_refund_id, refund_request_id
    INTO v_txn_status, v_txn_gateway_refund_id, v_request_id
    FROM refund_transactions
   WHERE id = p_transaction_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund transaction % not found', p_transaction_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Idempotency ─────────────────────────────────────────────────────────────
  IF v_txn_status = 'completed' THEN
    IF v_txn_gateway_refund_id = p_gateway_refund_id THEN
      -- Duplicate webhook delivery for a refund we already recorded.
      RETURN 'already_complete';
    END IF;
    -- Different refund ID on an already-completed transaction — data anomaly.
    -- This should never happen in production but raise rather than silently
    -- corrupt data.
    RAISE EXCEPTION
      'Transaction % is already completed with gateway_refund_id %. '
      'Refusing to overwrite with a different refund ID %.',
      p_transaction_id, v_txn_gateway_refund_id, p_gateway_refund_id
      USING ERRCODE = 'P0001';
  END IF;

  -- A transaction the Edge Function already marked as definitively failed
  -- (Razorpay 4xx) should not be overwritten by a later webhook event.
  -- The 4xx response is the more authoritative signal.  If this happens,
  -- the admin must investigate and resolve manually.
  IF v_txn_status = 'failed' THEN
    RETURN 'already_failed';
  END IF;

  IF v_txn_status NOT IN ('pending', 'processing') THEN
    RAISE EXCEPTION
      'Cannot complete transaction from unexpected status "%"', v_txn_status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Mark transaction complete ────────────────────────────────────────────────
  UPDATE refund_transactions
     SET status            = 'completed',
         gateway_refund_id = p_gateway_refund_id,
         gateway_response  = COALESCE(p_gateway_response, gateway_response),
         completed_at      = now(),
         updated_at        = now()
   WHERE id = p_transaction_id;

  -- ── Determine new ticket status ──────────────────────────────────────────────
  -- Identical logic to admin_mark_refund_transaction_complete (Phase 1 fix).
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

  UPDATE refund_requests
     SET status     = v_new_ticket_status,
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

-- ── webhook_fail_refund_transaction ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION webhook_fail_refund_transaction(
  p_transaction_id    UUID,
  p_gateway_refund_id TEXT,
  p_failure_reason    TEXT DEFAULT 'refund.failed webhook',
  p_gateway_response  JSONB DEFAULT NULL
)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_txn_status         TEXT;
  v_request_id         UUID;
  v_ticket_from_status TEXT;
BEGIN
  SELECT status, refund_request_id
    INTO v_txn_status, v_request_id
    FROM refund_transactions
   WHERE id = p_transaction_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund transaction % not found', p_transaction_id
      USING ERRCODE = 'P0002';
  END IF;

  -- A confirmed success is immutable — never revert it on a failure event.
  -- If Razorpay sends refund.failed for an already-completed refund, that is
  -- a Razorpay anomaly; the admin should investigate via the Razorpay dashboard.
  IF v_txn_status = 'completed' THEN
    RETURN 'already_complete';
  END IF;

  -- Idempotent re-delivery of a failure event.
  IF v_txn_status = 'failed' THEN
    RETURN 'already_failed';
  END IF;

  IF v_txn_status NOT IN ('pending', 'processing') THEN
    RAISE EXCEPTION
      'Cannot fail transaction from unexpected status "%"', v_txn_status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Mark transaction failed ──────────────────────────────────────────────────
  UPDATE refund_transactions
     SET status            = 'failed',
         failure_reason    = COALESCE(p_failure_reason, 'refund.failed webhook'),
         gateway_refund_id = COALESCE(p_gateway_refund_id, gateway_refund_id),
         gateway_response  = COALESCE(p_gateway_response, gateway_response),
         updated_at        = now()
   WHERE id = p_transaction_id;

  -- Fetch current ticket status for audit trail.
  SELECT status
    INTO v_ticket_from_status
    FROM refund_requests
   WHERE id = v_request_id
     FOR UPDATE;

  UPDATE refund_requests
     SET status     = 'failed',
         updated_at = now()
   WHERE id = v_request_id;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type, notes,
    metadata
  ) VALUES (
    v_request_id,
    v_ticket_from_status,
    'failed',
    NULL,
    'system',
    p_failure_reason,
    jsonb_build_object(
      'transaction_id',    p_transaction_id,
      'gateway_refund_id', p_gateway_refund_id,
      'source',            'razorpay_webhook'
    )
  );

  RETURN 'failed';
END;
$$;

GRANT EXECUTE ON FUNCTION webhook_fail_refund_transaction(UUID, TEXT, TEXT, JSONB)
  TO service_role;
