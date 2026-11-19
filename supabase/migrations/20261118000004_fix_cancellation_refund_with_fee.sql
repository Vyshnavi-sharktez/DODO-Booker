-- ─────────────────────────────────────────────────────────────────────────────
-- Update auto-refund trigger to deduct cancellation fee from refund amount.
--
-- When a customer cancels an online booking, the auto-refund trigger now
-- creates a refund for GREATEST(0, payment_amount - cancellation_fee_amount)
-- instead of the full payment amount.
--
-- If the entire payment is consumed by the fee (refund = 0), no refund request
-- is created.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_auto_create_cancellation_refund_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_request_id      UUID;
  v_ticket_number   TEXT;
  v_payment_id      UUID;
  v_payment_amount  NUMERIC;
  v_refund_amount   NUMERIC;
  v_category_id     UUID;
  v_customer_name   TEXT;
  v_booking_ref     TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM refund_requests WHERE booking_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  SELECT bp.id, bp.amount
    INTO v_payment_id, v_payment_amount
    FROM booking_payments bp
   WHERE bp.booking_id = NEW.id
     AND bp.status = 'success'
   ORDER BY bp.attempt_number DESC
   LIMIT 1;

  v_payment_amount := COALESCE(v_payment_amount, NEW.total_amount);

  -- Deduct cancellation fee from refund
  v_refund_amount := GREATEST(0, v_payment_amount - COALESCE(NEW.cancellation_fee_amount, 0));

  -- Nothing to refund if net amount is zero or negative
  IF v_refund_amount <= 0 THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_category_id
    FROM refund_issue_categories
   WHERE key = 'booking_cancelled_by_customer'
   LIMIT 1;

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
    CASE
      WHEN COALESCE(NEW.cancellation_fee_amount, 0) > 0
        THEN 'Auto-generated: booking cancelled — ₹' || ROUND(NEW.cancellation_fee_amount, 0)::TEXT
             || ' cancellation fee deducted; ₹' || ROUND(v_refund_amount, 0)::TEXT || ' refunded.'
      ELSE 'Auto-generated: booking cancelled — online payment refund.'
    END,
    v_refund_amount,
    '[]'::JSONB,
    0,
    'online',
    v_payment_amount,
    'approved',
    now()
  )
  RETURNING id, ticket_number INTO v_request_id, v_ticket_number;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type, notes
  ) VALUES (
    v_request_id, NULL, 'approved',
    NULL, 'system',
    'Booking cancelled — refund auto-approved.'
  );

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
      || CASE
           WHEN COALESCE(NEW.cancellation_fee_amount, 0) > 0
             THEN ' — ₹' || ROUND(NEW.cancellation_fee_amount, 0)::TEXT || ' fee charged,'
                  || ' ₹' || ROUND(v_refund_amount, 0)::TEXT || ' to be refunded ('
           ELSE ' — ₹' || ROUND(v_refund_amount, 0)::TEXT || ' to be refunded ('
         END
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

-- Trigger already exists (created in 20260923000015); OR-REPLACE above is enough.
-- Re-create to ensure correct trigger definition in case it was dropped.
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
