-- Fix: admin "New Booking" notification was firing on booking INSERT (before Razorpay)
-- for online-payment bookings. The DB trigger trg_notify_admin_new_booking fires on
-- AFTER INSERT WHERE status='pending', which is too early — the customer is still inside
-- the Razorpay checkout modal.
--
-- Correct flow for online payments:
--   INSERT booking (status=pending, payment_method=online)  ← no admin notification yet
--   Customer pays via Razorpay
--   verify-razorpay-payment Edge Function updates payment_status='success'  ← notify HERE
--
-- Changes:
--   1. Recreate trg_notify_admin_new_booking to skip online-payment bookings at INSERT.
--   2. Add trg_notify_admin_online_payment_confirmed that fires when payment_status
--      transitions to 'success' for an online-payment booking.
--   3. Update fn_notify_admin_booking_status_change to suppress the "Booking Cancelled"
--      admin notification for payment-abandoned bookings (payment never completed, so
--      admin never received "New Booking" — sending "Cancelled" would be confusing noise).

-- ── 1. INSERT trigger: skip online-payment bookings ─────────────────────────────
DROP TRIGGER IF EXISTS trg_notify_admin_new_booking ON bookings;
CREATE TRIGGER trg_notify_admin_new_booking
  AFTER INSERT ON bookings
  FOR EACH ROW
  WHEN (
    NEW.status = 'pending'
    AND (NEW.payment_method IS NULL OR NEW.payment_method NOT IN ('online', 'razorpay'))
  )
  EXECUTE FUNCTION fn_notify_admin_new_booking();

-- ── 2. UPDATE trigger: notify admin when online payment is verified ──────────────
DROP TRIGGER IF EXISTS trg_notify_admin_online_payment_confirmed ON bookings;
CREATE TRIGGER trg_notify_admin_online_payment_confirmed
  AFTER UPDATE OF payment_status ON bookings
  FOR EACH ROW
  WHEN (
    OLD.payment_status IS DISTINCT FROM 'success'
    AND NEW.payment_status = 'success'
    AND NEW.payment_method IN ('online', 'razorpay')
  )
  EXECUTE FUNCTION fn_notify_admin_new_booking();

-- ── 3. Suppress "Booking Cancelled" noise for payment-abandoned bookings ─────────
-- Redefine fn_notify_admin_booking_status_change to skip cancellations when
-- cancellation_reason='payment_failed' and the online payment was never completed.
-- Preserves the ::UUID cast fix from migration 20261006000008.
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
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('cancelled', 'cancelled_by_customer', 'completed', 'rejected') THEN
    RETURN NEW;
  END IF;

  -- Suppress cancellation notification for payment-abandoned online bookings.
  -- Admin never received "New Booking" for these, so "Booking Cancelled" is noise.
  IF NEW.status = 'cancelled'
     AND NEW.payment_method IN ('online', 'razorpay')
     AND (NEW.payment_status IS NULL OR NEW.payment_status <> 'success')
     AND NEW.cancellation_reason = 'payment_failed' THEN
    RETURN NEW;
  END IF;

  v_notif_type := CASE NEW.status
    WHEN 'cancelled'             THEN 'booking_cancelled'
    WHEN 'cancelled_by_customer' THEN 'booking_cancelled'
    WHEN 'completed'             THEN 'booking_completed'
    WHEN 'rejected'              THEN 'booking_rejected'
  END;

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
  WHERE  id = NEW.customer_id::UUID;
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
