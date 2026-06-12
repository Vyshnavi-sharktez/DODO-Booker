-- Migration: Automatic customer notification on vendor assignment
-- Fires a DB trigger whenever bookings.vendor_id transitions NULL → a vendor UUID.
-- Run this in Supabase Dashboard → SQL Editor.

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger function
-- SECURITY DEFINER so the function runs with owner privileges and can INSERT
-- into notifications even when RLS restricts the calling role.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_notify_customer_vendor_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vendor_name    TEXT;
  v_booking_ref    TEXT;
  v_already_exists BOOLEAN;
BEGIN
  -- Only act on the NULL → non-null transition of vendor_id.
  -- Reassignments (non-null → different non-null) are intentionally excluded.
  IF OLD.vendor_id IS NOT NULL OR NEW.vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_booking_ref := NEW.booking_number;

  RAISE LOG '[DODO][VendorAssignment] Assignment detected: booking % customer %',
    v_booking_ref, NEW.customer_id;

  -- Resolve vendor display name. Falls back gracefully if vendor row is missing.
  SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'the assigned vendor')
  INTO   v_vendor_name
  FROM   vendors
  WHERE  id = NEW.vendor_id;

  IF v_vendor_name IS NULL THEN
    v_vendor_name := 'the assigned vendor';
  END IF;

  -- Duplicate guard: if a vendor_assigned notification for this booking already
  -- exists (e.g. created by a concurrent path), skip silently.
  SELECT EXISTS (
    SELECT 1
    FROM   notifications
    WHERE  notification_type = 'vendor_assigned'
      AND  user_id           = NEW.customer_id
      AND  message           LIKE '%#' || v_booking_ref || '%'
  ) INTO v_already_exists;

  IF v_already_exists THEN
    RAISE LOG '[DODO][VendorAssignment] Duplicate prevented: booking % already notified',
      v_booking_ref;
    RETURN NEW;
  END IF;

  -- Insert customer notification.
  INSERT INTO notifications (
    user_type,
    user_id,
    title,
    message,
    notification_type,
    is_read,
    created_at
  ) VALUES (
    'customer',
    NEW.customer_id,
    'Vendor Assigned',
    'Your booking #' || v_booking_ref || ' has been assigned to ' || v_vendor_name || '.',
    'vendor_assigned',
    FALSE,
    NOW()
  );

  RAISE LOG '[DODO][VendorAssignment] Notification created: booking % → customer % (vendor: %)',
    v_booking_ref, NEW.customer_id, v_vendor_name;

  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger: fires AFTER UPDATE OF vendor_id FOR EACH ROW
-- Using OF vendor_id makes Postgres only invoke the trigger when that specific
-- column is included in the UPDATE statement, keeping overhead minimal.
-- ─────────────────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_notify_customer_vendor_assigned ON bookings;

CREATE TRIGGER trg_notify_customer_vendor_assigned
  AFTER UPDATE OF vendor_id ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_customer_vendor_assigned();
