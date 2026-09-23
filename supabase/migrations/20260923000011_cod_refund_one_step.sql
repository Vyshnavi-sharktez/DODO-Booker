-- ─────────────────────────────────────────────────────────────────────────────
-- COD Refund One-Step Flow
--
-- Replaces the old two-step flow (Initiate Transfer → Mark Complete + UTR)
-- with a single Admin action that atomically:
--   1. Creates a manual refund_transaction with status = 'completed'.
--   2. Transitions the ticket directly to 'completed'.
--   3. Writes a single status_history entry that fires the existing
--      fn_notify_on_refund_status_history_insert trigger, sending the customer
--      a refund_completed notification.
--
-- Safety guards preserved:
--   • fn_assert_active_admin() — caller must be an active admin.
--   • COD/cash payment method only.
--   • Ticket must be in an initiable status (approved / partially_approved / failed).
--   • bank_details_submitted_at must be set.
--   • Duplicate prevention: any non-failed transaction on the ticket blocks a
--     second initiation (row-level lock prevents concurrent races).
--   • Amount is capped at min(approved_amount, amount_paid) minus already-completed.
-- ─────────────────────────────────────────────────────────────────────────────

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

  -- Lock ticket row to prevent concurrent duplicate initiation.
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

  -- COD/cash bookings only.
  IF v_payment_method NOT IN ('cod', 'cash') THEN
    RAISE EXCEPTION
      'admin_initiate_cod_refund is only for COD/cash bookings (got: "%")',
      v_payment_method
      USING ERRCODE = 'P0001';
  END IF;

  -- Ticket must be in an initiable status.
  IF v_current_status NOT IN ('approved', 'partially_approved', 'failed') THEN
    RAISE EXCEPTION
      'Cannot initiate refund from status "%". '
      'Ticket must be approved or partially_approved.',
      v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  -- Customer must have submitted bank/UPI details.
  IF v_bank_submitted_at IS NULL THEN
    RAISE EXCEPTION
      'Cannot initiate COD refund until the customer has submitted '
      'their bank/UPI details'
      USING ERRCODE = 'P0001';
  END IF;

  -- Duplicate prevention: block if any non-failed transaction already exists
  -- (pending/processing means in-flight; completed means already done).
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

  -- Refund amount = min(approved_amount, amount_paid) minus any prior
  -- completed transactions (handles partial-refund retry scenarios).
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

  -- Insert transaction directly as completed (no pending/processing phase).
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

  -- Transition ticket directly to 'completed'.
  UPDATE refund_requests
     SET status     = 'completed',
         updated_at = now()
   WHERE id = p_request_id;

  -- Single history entry: from_status → 'completed'.
  -- The fn_notify_on_refund_status_history_insert trigger fires here and
  -- sends the customer a refund_completed notification automatically.
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
