-- ─────────────────────────────────────────────────────────────────────────────
-- Refund Notification Triggers
--
-- Two AFTER INSERT triggers wire the existing `notifications` table into the
-- refund workflow so that both customers and admins are notified at the correct
-- authoritative backend events — not from Flutter UI callbacks.
--
-- Trigger 1 (refund_status_history INSERT):
--   • New customer-submitted ticket  → admin broadcast notification
--   • Ticket status change by admin/system → customer notification
--   • Payment failure (online)       → additional admin notification
--
-- Trigger 2 (refund_messages INSERT):
--   • Customer message (non-internal) → admin broadcast notification
--   • Admin message (non-internal)    → customer notification
--
-- Design rules:
--   • SECURITY DEFINER so triggers can INSERT into notifications without RLS.
--   • EXCEPTION handlers so a notification failure NEVER rolls back the parent
--     refund operation (requirement: notification failures must be non-fatal).
--   • Duplicate prevention on admin "new request" notification.
--   • No sensitive fields (bank_upi_details, admin_notes, etc.) are copied.
--   • entity_type = 'refund_request', entity_id = refund_requests.id so both
--     apps can deep-link into the relevant ticket screen.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Trigger 1: refund_status_history → customer + admin notifications ─────────

CREATE OR REPLACE FUNCTION fn_notify_on_refund_status_history_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket_number   TEXT;
  v_customer_id     UUID;
  v_approved_amount NUMERIC;
  v_pay_method      TEXT;
  v_requested_amount NUMERIC;
  v_customer_name   TEXT;
  v_booking_ref     TEXT;
  v_notif_type      TEXT;
  v_title           TEXT;
  v_message         TEXT;
  v_amount_str      TEXT;
BEGIN
  -- ── Fetch refund request context ────────────────────────────────────────────
  SELECT rr.ticket_number,
         rr.customer_id,
         rr.approved_amount,
         rr.payment_method_snapshot,
         rr.requested_amount
    INTO v_ticket_number, v_customer_id, v_approved_amount,
         v_pay_method, v_requested_amount
    FROM refund_requests rr
   WHERE rr.id = NEW.refund_request_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- ── A. Admin notified: new customer-submitted ticket ─────────────────────────
  IF NEW.from_status IS NULL
     AND NEW.to_status = 'submitted'
     AND NEW.changed_by_type = 'customer' THEN

    -- Duplicate guard: skip if admin already notified for this ticket.
    IF EXISTS (
      SELECT 1 FROM notifications
       WHERE notification_type = 'refund_new_request'
         AND entity_type       = 'refund_request'
         AND entity_id         = NEW.refund_request_id
    ) THEN
      RETURN NEW;
    END IF;

    SELECT COALESCE(NULLIF(TRIM(c.full_name), ''), 'A customer')
      INTO v_customer_name
      FROM customers c
     WHERE c.id = v_customer_id;
    v_customer_name := COALESCE(v_customer_name, 'A customer');

    SELECT COALESCE(b.booking_number, 'BK-' || UPPER(LEFT(b.id::TEXT, 8)))
      INTO v_booking_ref
      FROM bookings b
      JOIN refund_requests rr ON rr.booking_id = b.id
     WHERE rr.id = NEW.refund_request_id;
    v_booking_ref := COALESCE(v_booking_ref, 'unknown');

    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'admin', NULL,
      'New Refund Request',
      v_customer_name
        || ' submitted refund request ' || v_ticket_number
        || ' for ₹' || ROUND(v_requested_amount, 0)::TEXT
        || ' (booking ' || v_booking_ref || ').',
      'refund_new_request', 'refund_request', NEW.refund_request_id,
      FALSE, NOW()
    );

    RETURN NEW;
  END IF;

  -- ── B. Customer notified: status change by admin or system ───────────────────
  IF NEW.changed_by_type NOT IN ('admin', 'system') THEN
    RETURN NEW;
  END IF;

  v_amount_str := '₹' || ROUND(COALESCE(v_approved_amount, v_requested_amount, 0), 0)::TEXT;

  v_notif_type := CASE NEW.to_status
    WHEN 'under_review'        THEN 'refund_under_review'
    WHEN 'more_info_requested' THEN 'refund_more_info_requested'
    WHEN 'approved'            THEN 'refund_approved'
    WHEN 'partially_approved'  THEN 'refund_partially_approved'
    WHEN 'rejected'            THEN 'refund_rejected'
    WHEN 'processing'          THEN 'refund_processing'
    WHEN 'completed'           THEN 'refund_completed'
    WHEN 'failed'              THEN 'refund_failed'
    WHEN 'closed'              THEN 'refund_closed'
    ELSE NULL
  END;

  IF v_notif_type IS NULL THEN
    RETURN NEW;
  END IF;

  v_title := CASE NEW.to_status
    WHEN 'under_review'        THEN 'Refund Under Review'
    WHEN 'more_info_requested' THEN 'More Information Needed'
    WHEN 'approved'            THEN 'Refund Approved'
    WHEN 'partially_approved'  THEN 'Partial Refund Approved'
    WHEN 'rejected'            THEN 'Refund Request Rejected'
    WHEN 'processing'          THEN 'Refund Initiated'
    WHEN 'completed'           THEN 'Refund Completed'
    WHEN 'failed'              THEN 'Refund Processing Issue'
    WHEN 'closed'              THEN 'Refund Ticket Closed'
  END;

  v_message := CASE NEW.to_status
    WHEN 'under_review' THEN
      'Your refund request ' || v_ticket_number || ' is being reviewed by our team.'
    WHEN 'more_info_requested' THEN
      'We need additional information about your refund request ' || v_ticket_number || '. Please check the ticket for details.'
    WHEN 'approved' THEN
      'Your refund request ' || v_ticket_number || ' has been approved for ' || v_amount_str || '.'
    WHEN 'partially_approved' THEN
      'Your refund request ' || v_ticket_number || ' has been partially approved for ' || v_amount_str || '.'
    WHEN 'rejected' THEN
      'Your refund request ' || v_ticket_number || ' could not be approved. Tap to view the details.'
    WHEN 'processing' THEN
      'Your refund for ' || v_ticket_number || ' has been initiated and is being processed.'
    WHEN 'completed' THEN
      CASE WHEN v_pay_method IN ('cod', 'cash')
           THEN 'Your refund of ' || v_amount_str || ' for ' || v_ticket_number || ' has been transferred to your bank/UPI account.'
           ELSE 'Your refund of ' || v_amount_str || ' for ' || v_ticket_number || ' has been successfully processed to your original payment method.'
      END
    WHEN 'failed' THEN
      'There was an issue processing your refund for ' || v_ticket_number || '. Our team will look into this.'
    WHEN 'closed' THEN
      'Your refund request ' || v_ticket_number || ' has been closed.'
  END;

  -- Insert customer notification.
  INSERT INTO notifications (
    user_type, user_id, title, message,
    notification_type, entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'customer', v_customer_id,
    v_title, v_message,
    v_notif_type, 'refund_request', NEW.refund_request_id,
    FALSE, NOW()
  );

  -- ── C. Admin also notified on online payment failure ─────────────────────────
  IF NEW.to_status = 'failed' AND v_pay_method NOT IN ('cod', 'cash') THEN
    SELECT COALESCE(NULLIF(TRIM(c.full_name), ''), 'A customer')
      INTO v_customer_name
      FROM customers c
     WHERE c.id = v_customer_id;
    v_customer_name := COALESCE(v_customer_name, 'A customer');

    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'admin', NULL,
      'Razorpay Refund Failed',
      'Razorpay refund failed for ticket ' || v_ticket_number
        || ' (' || v_customer_name || '). Manual review required.',
      'refund_payment_failed', 'refund_request', NEW.refund_request_id,
      FALSE, NOW()
    );
  END IF;

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][RefundNotif] fn_notify_on_refund_status_history_insert failed for request %: %',
      NEW.refund_request_id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_refund_status_history_insert ON refund_status_history;
CREATE TRIGGER trg_notify_on_refund_status_history_insert
  AFTER INSERT ON refund_status_history
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_on_refund_status_history_insert();

-- ── Trigger 2: refund_messages → cross-party notifications ───────────────────

CREATE OR REPLACE FUNCTION fn_notify_on_refund_message_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket_number TEXT;
  v_customer_id   UUID;
  v_customer_name TEXT;
BEGIN
  -- Internal admin notes are not surfaced to customers.
  IF NEW.is_internal THEN
    RETURN NEW;
  END IF;

  SELECT rr.ticket_number, rr.customer_id
    INTO v_ticket_number, v_customer_id
    FROM refund_requests rr
   WHERE rr.id = NEW.refund_request_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF NEW.sender_type = 'customer' THEN
    -- ── Customer message → notify all admins ──────────────────────────────────
    SELECT COALESCE(NULLIF(TRIM(c.full_name), ''), 'A customer')
      INTO v_customer_name
      FROM customers c
     WHERE c.id = v_customer_id;
    v_customer_name := COALESCE(v_customer_name, 'A customer');

    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'admin', NULL,
      'Customer Message',
      v_customer_name || ' sent a message on refund request ' || v_ticket_number || '.',
      'refund_customer_message', 'refund_request', NEW.refund_request_id,
      FALSE, NOW()
    );

  ELSIF NEW.sender_type = 'admin' THEN
    -- ── Admin message → notify the customer ──────────────────────────────────
    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'customer', v_customer_id,
      'New Message on Your Refund',
      'You have a new message regarding your refund request ' || v_ticket_number || '.',
      'refund_admin_message', 'refund_request', NEW.refund_request_id,
      FALSE, NOW()
    );
  END IF;

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][RefundNotif] fn_notify_on_refund_message_insert failed for request %: %',
      NEW.refund_request_id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_refund_message_insert ON refund_messages;
CREATE TRIGGER trg_notify_on_refund_message_insert
  AFTER INSERT ON refund_messages
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_on_refund_message_insert();
