-- Admin notification triggers for booking lifecycle events and customer reviews.
--
-- New notifications added:
--   new_booking           – fires on bookings INSERT (status = 'pending')
--   booking_cancelled     – fires on bookings UPDATE → 'cancelled' | 'cancelled_by_customer'
--   booking_completed     – fires on bookings UPDATE → 'completed'
--   booking_rejected      – fires on bookings UPDATE → 'rejected'
--   new_review            – fires on customer_reviews INSERT
--
-- All booking-lifecycle notifications use entity_type = 'booking' and
-- entity_id = bookings.id so the admin panel can open BookingDetailsDialog
-- directly from the notification.

-- ── 1. New booking created ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_notify_admin_new_booking()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name TEXT;
  v_booking_num   TEXT;
  v_message       TEXT;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'A customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  v_booking_num := COALESCE(NEW.booking_number, LEFT(NEW.id::TEXT, 8));

  v_message := v_customer_name
    || ' placed a new booking (#' || v_booking_num || ')'
    || ' for ₹' || ROUND(NEW.total_amount, 0)::TEXT || '.';

  IF NEW.is_amc IS TRUE THEN
    v_message := v_message || ' (AMC)';
  END IF;

  INSERT INTO notifications (
    user_type, user_id,
    title, message,
    notification_type, entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'admin', NULL,
    'New Booking', v_message,
    'new_booking', 'booking', NEW.id,
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_new_booking ON bookings;
CREATE TRIGGER trg_notify_admin_new_booking
  AFTER INSERT ON bookings
  FOR EACH ROW
  WHEN (NEW.status = 'pending')
  EXECUTE FUNCTION fn_notify_admin_new_booking();

-- ── 2. Booking status change (cancelled / completed / rejected) ────────────────

CREATE OR REPLACE FUNCTION fn_notify_admin_booking_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name TEXT;
  v_booking_num   TEXT;
  v_notif_type    TEXT;
  v_title         TEXT;
  v_message       TEXT;
BEGIN
  -- Only react to actual status transitions toward notable states.
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('cancelled', 'cancelled_by_customer', 'completed', 'rejected') THEN
    RETURN NEW;
  END IF;

  -- Determine notification type from new status.
  v_notif_type := CASE NEW.status
    WHEN 'cancelled'            THEN 'booking_cancelled'
    WHEN 'cancelled_by_customer' THEN 'booking_cancelled'
    WHEN 'completed'            THEN 'booking_completed'
    WHEN 'rejected'             THEN 'booking_rejected'
  END;

  -- Duplicate guard: prevent repeat notifications if trigger fires twice.
  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE entity_type       = 'booking'
      AND entity_id         = NEW.id
      AND notification_type = v_notif_type
  ) THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'A customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  v_booking_num := COALESCE(NEW.booking_number, LEFT(NEW.id::TEXT, 8));

  IF NEW.status IN ('cancelled', 'cancelled_by_customer') THEN
    v_title   := 'Booking Cancelled';
    v_message := 'Booking #' || v_booking_num || ' by ' || v_customer_name || ' was cancelled.';

  ELSIF NEW.status = 'completed' THEN
    v_title   := 'Booking Completed';
    v_message := 'Booking #' || v_booking_num || ' by ' || v_customer_name || ' has been completed.';

  ELSIF NEW.status = 'rejected' THEN
    v_title   := 'Booking Rejected';
    v_message := 'Booking #' || v_booking_num || ' was rejected by the vendor.';
    IF NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> '' THEN
      v_message := v_message || ' Reason: ' || TRIM(NEW.rejection_reason) || '.';
    END IF;
  END IF;

  INSERT INTO notifications (
    user_type, user_id,
    title, message,
    notification_type, entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'admin', NULL,
    v_title, v_message,
    v_notif_type, 'booking', NEW.id,
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_booking_status_change ON bookings;
CREATE TRIGGER trg_notify_admin_booking_status_change
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_admin_booking_status_change();

-- ── 3. New customer review ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_notify_admin_new_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name TEXT;
  v_booking_num   TEXT;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'A customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  SELECT COALESCE(booking_number, LEFT(id::TEXT, 8))
  INTO   v_booking_num
  FROM   bookings
  WHERE  id = NEW.booking_id;
  v_booking_num := COALESCE(v_booking_num, LEFT(NEW.booking_id::TEXT, 8));

  INSERT INTO notifications (
    user_type, user_id,
    title, message,
    notification_type, entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'admin', NULL,
    'New Review',
    v_customer_name
      || ' left a ' || NEW.rating::TEXT || '★ review on booking #'
      || v_booking_num || '.',
    'new_review', 'booking', NEW.booking_id,
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_new_review ON customer_reviews;
CREATE TRIGGER trg_notify_admin_new_review
  AFTER INSERT ON customer_reviews
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_admin_new_review();
