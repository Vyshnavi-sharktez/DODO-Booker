-- Rollback: remove booking notification template system.
--
-- The template trigger (trg_notify_customer_booking_status_change) proved
-- unreliable: the trigger function referenced a non-existent column
-- (bi.catalog_node_id instead of bi.service_id), and EXCEPTION WHEN OTHERS
-- silently swallowed every error, resulting in zero customer notifications.
--
-- This migration:
--   1. Drops the template trigger, function, RPCs, and table.
--   2. Restores fn_notify_admin_booking_status_change to include customer
--      notifications for admin-initiated and vendor-initiated cancellations
--      (removed by 20261009000001 in favour of the now-dropped template trigger).
--
-- Vendor-assignment customer notifications are handled by Flutter-side
-- createNotification() calls; the DB trigger fn_notify_customer_vendor_assigned
-- is intentionally NOT recreated to avoid duplicates.

-- ── 1. Drop template trigger and function ─────────────────────────────────────

DROP TRIGGER  IF EXISTS trg_notify_customer_booking_status_change ON bookings;
DROP FUNCTION IF EXISTS fn_notify_customer_booking_status_change();

-- ── 2. Drop RPC helpers ───────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS get_booking_notification_templates();
DROP FUNCTION IF EXISTS update_booking_notification_template(TEXT, TEXT, TEXT, TEXT, BOOLEAN);

-- ── 3. Drop table (CASCADE removes RLS policies automatically) ────────────────

DROP TABLE IF EXISTS booking_notification_templates CASCADE;

-- ── 4. Restore fn_notify_admin_booking_status_change ─────────────────────────
-- Restores the version from 20260928000004 + payment_failed suppression from
-- 20261008000005. Key difference from 20261009000001: re-adds customer INSERTs
-- for admin-cancelled and vendor-cancelled branches that were removed when the
-- template trigger was expected to handle them.

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
  v_message       TEXT;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('cancelled', 'cancelled_by_customer', 'completed', 'rejected') THEN
    RETURN NEW;
  END IF;

  -- Suppress all notifications for payment-abandoned online bookings.
  -- Admin never received "New Booking" for these, so any status noise is unwanted.
  IF NEW.status = 'cancelled'
     AND NEW.payment_method IN ('online', 'razorpay')
     AND (NEW.payment_status IS NULL OR NEW.payment_status <> 'success')
     AND NEW.cancellation_reason = 'payment_failed' THEN
    RETURN NEW;
  END IF;

  -- ── Common lookups ─────────────────────────────────────────────────────────
  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'A customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id::UUID;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  v_booking_num := COALESCE(NEW.booking_number, LEFT(NEW.id::TEXT, 8));

  -- ── COMPLETED — admin notification only ──────────────────────────────────
  IF NEW.status = 'completed' THEN
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

  -- ── REJECTED — admin notification only ───────────────────────────────────
  IF NEW.status = 'rejected' THEN
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

  -- ── CANCELLED — route by cancelled_by ─────────────────────────────────────
  v_reason_clause := CASE
    WHEN NEW.cancellation_reason IS NOT NULL
         AND TRIM(NEW.cancellation_reason) <> ''
    THEN ' Reason: ' || TRIM(NEW.cancellation_reason) || '.'
    ELSE ''
  END;

  -- ADMIN cancelled: notify customer + vendor; skip admin (they performed the action).
  IF NEW.cancelled_by = 'admin' THEN
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_cancelled' AND user_type = 'customer'
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

    IF NEW.vendor_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM notifications
         WHERE entity_type = 'booking' AND entity_id = NEW.id
           AND notification_type = 'booking_cancelled' AND user_type = 'vendor'
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
    RETURN NEW;
  END IF;

  -- VENDOR cancelled: notify admin + customer; skip vendor (they performed the action).
  IF NEW.cancelled_by = 'vendor' THEN
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_cancelled' AND user_type = 'admin'
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

    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_cancelled' AND user_type = 'customer'
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
    RETURN NEW;
  END IF;

  -- CUSTOMER cancelled (or legacy cancelled_by_customer / NULL):
  -- notify admin + vendor; skip customer (they performed the action).
  IF NOT EXISTS (
    SELECT 1 FROM notifications
    WHERE entity_type = 'booking' AND entity_id = NEW.id
      AND notification_type = 'booking_cancelled' AND user_type = 'admin'
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

  IF NEW.vendor_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM notifications
       WHERE entity_type = 'booking' AND entity_id = NEW.id
         AND notification_type = 'booking_cancelled' AND user_type = 'vendor'
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

  RETURN NEW;
END;
$$;

-- Recreate trigger (function body changed; trigger definition is unchanged).
DROP TRIGGER IF EXISTS trg_notify_admin_booking_status_change ON bookings;
CREATE TRIGGER trg_notify_admin_booking_status_change
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_admin_booking_status_change();
