-- Fix booking cancellation notification routing.
--
-- Problem: fn_notify_admin_booking_status_change always sends to 'admin' for
-- every cancellation, regardless of who initiated it. This causes:
--   • Admin cancels → admin gets notified about their own action; customer
--     and vendor receive nothing.
--   • Customer cancels → admin gets duplicate notifications (trigger + Dart).
--
-- Fix: re-route based on cancelled_by column.
--
--   cancelled_by = 'admin':
--     • Notify customer  — "Your booking was cancelled by our team."
--     • Notify vendor    — "Booking #X was cancelled by the team."  (if assigned)
--     • Do NOT notify admin (they performed the action)
--     • Include cancellation_reason when present
--
--   cancelled_by = 'customer'  OR  status = 'cancelled_by_customer' (legacy):
--     • Notify admin    — "Booking #X by Customer was cancelled."
--     • Notify vendor   — "Booking #X was cancelled by the customer."  (if assigned)
--     • Do NOT notify customer (they performed the action)
--
--   cancelled_by = 'vendor':
--     • Notify admin    — existing broadcast
--     • Notify customer — "Your booking was cancelled by the service provider."
--     • Do NOT notify vendor (they performed the action)
--
--   cancelled_by IS NULL (legacy / unknown):
--     • Notify admin only  — fallback, same as before
--
-- status = 'completed' and status = 'rejected' rows are unchanged.
--
-- Companion Dart change: customer app bookings_service.dart no longer inserts
-- admin or vendor notifications for customer-initiated cancellations; the trigger
-- handles both, eliminating the duplicate admin notification.

CREATE OR REPLACE FUNCTION fn_notify_admin_booking_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name TEXT;
  v_booking_num   TEXT;
  v_reason_clause TEXT;
  v_notif_type    TEXT;
  v_title         TEXT;
  v_message       TEXT;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('cancelled', 'cancelled_by_customer', 'completed', 'rejected') THEN
    RETURN NEW;
  END IF;

  -- ── Common lookups ──────────────────────────────────────────────────────────
  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'A customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  v_booking_num := COALESCE(NEW.booking_number, LEFT(NEW.id::TEXT, 8));

  -- ── COMPLETED / REJECTED — unchanged behaviour (admin only) ────────────────
  IF NEW.status = 'completed' THEN
    v_notif_type := 'booking_completed';
    IF EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_completed'
    ) THEN RETURN NEW; END IF;

    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'admin', NULL,
      'Booking Completed',
      'Booking #' || v_booking_num || ' by ' || v_customer_name || ' has been completed.',
      'booking_completed', 'booking', NEW.id, FALSE, NOW()
    );
    RETURN NEW;
  END IF;

  IF NEW.status = 'rejected' THEN
    v_notif_type := 'booking_rejected';
    IF EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_rejected'
    ) THEN RETURN NEW; END IF;

    v_message := 'Booking #' || v_booking_num || ' was rejected by the vendor.';
    IF NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> '' THEN
      v_message := v_message || ' Reason: ' || TRIM(NEW.rejection_reason) || '.';
    END IF;

    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'admin', NULL, 'Booking Rejected', v_message,
      'booking_rejected', 'booking', NEW.id, FALSE, NOW()
    );
    RETURN NEW;
  END IF;

  -- ── CANCELLED — route by cancelled_by ──────────────────────────────────────

  -- Build reason clause (shared across all cancellation messages).
  IF NEW.cancellation_reason IS NOT NULL
     AND TRIM(NEW.cancellation_reason) <> '' THEN
    v_reason_clause := ' Reason: ' || TRIM(NEW.cancellation_reason) || '.';
  ELSE
    v_reason_clause := '';
  END IF;

  -- ── ADMIN cancelled ─────────────────────────────────────────────────────────
  IF NEW.cancelled_by = 'admin' THEN
    -- Notify customer (personal).
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_cancelled'
        AND user_type = 'customer'
    ) THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'customer', NEW.customer_id,
        'Booking Cancelled',
        'Your booking #' || v_booking_num ||
          ' has been cancelled by our team.' || v_reason_clause,
        'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
      );
    END IF;

    -- Notify vendor (personal) if one is assigned.
    IF NEW.vendor_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM notifications
         WHERE entity_type = 'booking' AND entity_id = NEW.id
           AND notification_type = 'booking_cancelled'
           AND user_type = 'vendor'
       )
    THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id,
        'Booking Cancelled',
        'Booking #' || v_booking_num ||
          ' has been cancelled by the team.' || v_reason_clause,
        'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
      );
    END IF;

    RAISE LOG '[DODO][BookingCancel] Admin-initiated cancel for % — customer % notified, vendor % notified',
      NEW.id, NEW.customer_id, NEW.vendor_id;

    RETURN NEW;
  END IF;

  -- ── VENDOR cancelled ────────────────────────────────────────────────────────
  IF NEW.cancelled_by = 'vendor' THEN
    -- Notify admin (broadcast).
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_cancelled'
        AND user_type = 'admin'
    ) THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'admin', NULL,
        'Booking Cancelled',
        'Booking #' || v_booking_num || ' by ' || v_customer_name ||
          ' was cancelled by the vendor.' || v_reason_clause,
        'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
      );
    END IF;

    -- Notify customer (personal).
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_cancelled'
        AND user_type = 'customer'
    ) THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'customer', NEW.customer_id,
        'Booking Cancelled',
        'Your booking #' || v_booking_num ||
          ' was cancelled by the service provider.' || v_reason_clause,
        'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
      );
    END IF;

    RAISE LOG '[DODO][BookingCancel] Vendor-initiated cancel for % — admin + customer % notified',
      NEW.id, NEW.customer_id;

    RETURN NEW;
  END IF;

  -- ── CUSTOMER cancelled  (or legacy cancelled_by_customer status / NULL) ─────
  -- Notify admin (broadcast).
  IF NOT EXISTS (
    SELECT 1 FROM notifications
    WHERE entity_type = 'booking' AND entity_id = NEW.id
      AND notification_type = 'booking_cancelled'
      AND user_type = 'admin'
  ) THEN
    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'admin', NULL,
      'Booking Cancelled',
      'Booking #' || v_booking_num || ' by ' || v_customer_name || ' was cancelled.',
      'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
    );
  END IF;

  -- Notify vendor (personal) if assigned.
  IF NEW.vendor_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM notifications
       WHERE entity_type = 'booking' AND entity_id = NEW.id
         AND notification_type = 'booking_cancelled'
         AND user_type = 'vendor'
     )
  THEN
    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'vendor', NEW.vendor_id,
      'Booking Cancelled',
      'Booking #' || v_booking_num || ' has been cancelled by the customer.',
      'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
    );
  END IF;

  RAISE LOG '[DODO][BookingCancel] Customer-initiated cancel for % — admin notified, vendor % notified',
    NEW.id, NEW.vendor_id;

  RETURN NEW;
END;
$$;

-- Trigger definition is unchanged — only the function body above changed.
DROP TRIGGER IF EXISTS trg_notify_admin_booking_status_change ON bookings;
CREATE TRIGGER trg_notify_admin_booking_status_change
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_admin_booking_status_change();
