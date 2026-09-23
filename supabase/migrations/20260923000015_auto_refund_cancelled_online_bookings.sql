-- ─────────────────────────────────────────────────────────────────────────────
-- Auto-create approved refund request for cancelled online bookings.
--
-- When a booking with a captured online payment (payment_status = 'success',
-- payment_method IN ('online', 'razorpay')) transitions to a cancelled state,
-- this trigger automatically:
--   1. Creates an approved refund_request for the full captured amount.
--   2. Writes a status history entry (NULL → 'approved', changed_by = system),
--      which fires the existing fn_notify_on_refund_status_history_insert and
--      sends the customer a "Refund Approved" notification.
--   3. Inserts an admin broadcast notification with
--      entity_type = 'refund_request' so the admin can deep-link directly into
--      the RefundDetailDialog and initiate the Razorpay refund.
--
-- Admin processes the refund by clicking "Initiate Refund" in the RefundDetailDialog
-- — the existing process-razorpay-refund edge function handles the rest.
--
-- Idempotency: if a refund_request already exists for this booking, the trigger
-- silently skips to prevent duplicates on repeated UPDATE calls.
--
-- The EXCEPTION handler ensures that a failure in this trigger can never roll
-- back the parent booking cancellation.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_auto_create_cancellation_refund_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_request_id        UUID;
  v_ticket_number     TEXT;
  v_payment_id        UUID;
  v_payment_amount    NUMERIC;
  v_category_id       UUID;
  v_customer_name     TEXT;
  v_booking_ref       TEXT;
BEGIN
  -- Idempotency: skip if any refund_request already exists for this booking.
  IF EXISTS (
    SELECT 1 FROM refund_requests WHERE booking_id = NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  -- Resolve the most recent successful booking_payment for amount + id.
  SELECT bp.id, bp.amount
    INTO v_payment_id, v_payment_amount
    FROM booking_payments bp
   WHERE bp.booking_id = NEW.id
     AND bp.status = 'success'
   ORDER BY bp.attempt_number DESC
   LIMIT 1;

  -- Fall back to booking total if no booking_payments row found.
  v_payment_amount := COALESCE(v_payment_amount, NEW.total_amount);

  -- Sanity check: nothing to refund if amount is zero or negative.
  IF v_payment_amount <= 0 THEN
    RETURN NEW;
  END IF;

  -- Resolve issue category for cancellation (nullable if seed not yet applied).
  SELECT id INTO v_category_id
    FROM refund_issue_categories
   WHERE key = 'booking_cancelled_by_customer'
   LIMIT 1;

  -- Create the refund request in 'approved' state.
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
    status,
    approved_amount,
    reviewed_at
  ) VALUES (
    '',
    NEW.id,
    NEW.customer_id,
    v_payment_id,
    v_category_id,
    'Auto-generated: booking cancelled — online payment refund.',
    v_payment_amount,
    '[]'::JSONB,
    0,
    'online',
    v_payment_amount,
    'approved',
    now()
  )
  RETURNING id, ticket_number INTO v_request_id, v_ticket_number;

  -- History entry (NULL → approved, system).
  -- This fires fn_notify_on_refund_status_history_insert which sends the
  -- customer a "Refund Approved" push notification.
  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type,
    notes
  ) VALUES (
    v_request_id, NULL, 'approved',
    NULL, 'system',
    'Booking cancelled — refund auto-approved.'
  );

  -- Admin broadcast notification.
  v_booking_ref := COALESCE(
    NEW.booking_number,
    'BK-' || UPPER(LEFT(NEW.id::TEXT, 8))
  );

  SELECT COALESCE(NULLIF(TRIM(c.full_name), ''), 'A customer')
    INTO v_customer_name
    FROM customers c
   WHERE c.id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  INSERT INTO notifications (
    user_type, user_id,
    title, message,
    notification_type, entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'admin', NULL,
    'Cancellation Refund Required',
    'Booking #' || v_booking_ref
      || ' (' || v_customer_name || ') was cancelled'
      || ' — ₹' || ROUND(v_payment_amount, 0)::TEXT
      || ' online payment needs Razorpay refund ('
      || v_ticket_number || ').',
    'cancellation_refund_pending', 'refund_request', v_request_id,
    FALSE, NOW()
  );

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][Refund] fn_auto_create_cancellation_refund_request failed '
              'for booking %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_create_cancellation_refund_request ON bookings;
CREATE TRIGGER trg_auto_create_cancellation_refund_request
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  WHEN (
    NEW.status IN ('cancelled', 'cancelled_by_customer')
    AND OLD.status IS DISTINCT FROM NEW.status
    AND NEW.payment_status = 'success'
    AND NEW.payment_method IN ('online', 'razorpay')
  )
  EXECUTE FUNCTION fn_auto_create_cancellation_refund_request();
