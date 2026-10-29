-- Migration: 20261029000007_fix_subscription_purchase_notification.sql
-- Moves the admin "New Subscription Purchase" notification from INSERT time
-- (when the vendor initiates the flow) to activation time (when payment is
-- confirmed and status changes to 'active').
-- ─────────────────────────────────────────────────────────────────────────────

-- Drop the premature trigger that fires on INSERT (pending_payment status)
DROP TRIGGER IF EXISTS trg_notify_subscription_purchased ON vendor_subscriptions;

-- Update fn_notify_subscription_activated to also notify admins on activation.
-- Previously it only notified the vendor; now it notifies admins too.
CREATE OR REPLACE FUNCTION fn_notify_subscription_activated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_vendor_name TEXT;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  IF NEW.status <> 'active' THEN RETURN NEW; END IF;

  -- Vendor notification
  INSERT INTO notifications
    (user_type, user_id, title, message, notification_type, is_read, created_at)
  VALUES (
    'vendor', NEW.vendor_id,
    'Subscription Activated',
    'Your subscription is now active. Enjoy your plan benefits!',
    'subscription_activated',
    FALSE, NOW()
  );

  -- Admin notification (moved from fn_notify_subscription_purchased)
  SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'Unknown Vendor')
    INTO v_vendor_name
    FROM vendors WHERE id = NEW.vendor_id;

  INSERT INTO notifications
    (user_type, user_id, title, message, notification_type, is_read, created_at)
  SELECT
    'admin', au.id,
    'New Subscription Purchase',
    COALESCE(v_vendor_name, 'A vendor') || ' has purchased a subscription.',
    'subscription_purchased',
    FALSE, NOW()
  FROM admin_users au
  WHERE au.is_active = TRUE;

  RETURN NEW;
END;
$$;
