-- ── Vendor Subscription — Vendor-Driven Purchase Flow ─────────────────────────
--
-- Depends on: 20260727000001_vendor_subscriptions.sql
--             20260727000002_vendor_subscriptions_enforcement.sql
--
-- Changes:
--   1. Extend vendor_subscriptions.status CHECK: add 'pending_payment',
--      'pending_approval' (keeps 'pending' for backward compat)
--   2. Rebuild unique index to also block duplicate pending_payment records
--   3. Anon INSERT + UPDATE policies — vendors create/update their own
--      subscriptions and payment records via the purchase flow
--   4. Notification triggers:
--        a. fn_notify_subscription_purchased  — INSERT → admin notified
--        b. fn_notify_subscription_activated  — UPDATE status→active → vendor notified
--        c. fn_notify_payment_status_changed  — UPDATE payment.status → vendor notified
--
-- Safe to re-run: IF NOT EXISTS / CREATE OR REPLACE / ON CONFLICT throughout.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Extend status CHECK constraint ────────────────────────────────────────
--
-- The inline CHECK from the original migration has an auto-generated name.
-- We locate it dynamically and drop it before adding the named replacement.

DO $$
DECLARE v_cname TEXT;
BEGIN
  SELECT constraint_name INTO v_cname
    FROM information_schema.table_constraints
   WHERE table_name    = 'vendor_subscriptions'
     AND constraint_type = 'CHECK'
     AND constraint_name LIKE '%status%';
  IF v_cname IS NOT NULL THEN
    EXECUTE 'ALTER TABLE vendor_subscriptions DROP CONSTRAINT ' || quote_ident(v_cname);
  END IF;
END;
$$;

ALTER TABLE vendor_subscriptions
  ADD CONSTRAINT vendor_subscriptions_status_check
  CHECK (status IN (
    'pending_payment',
    'pending_approval',
    'pending',
    'active',
    'expired',
    'suspended',
    'cancelled'
  ));

-- ── 2. Rebuild unique index ───────────────────────────────────────────────────
--
-- Blocks a vendor from having more than one open subscription at a time.
-- Includes 'pending_payment' and 'pending_approval' so a vendor with an
-- in-flight purchase cannot start a second one.

DROP INDEX IF EXISTS uq_vendor_subscriptions_active;
CREATE UNIQUE INDEX IF NOT EXISTS uq_vendor_subscriptions_active
  ON vendor_subscriptions(vendor_id)
  WHERE status IN ('active', 'pending', 'pending_payment', 'pending_approval');

-- ── 3. Anon write policies for vendor purchase flow ───────────────────────────
--
-- The vendor app authenticates via custom phone+OTP (anon Supabase role).
-- Application-layer vendor_id filtering prevents cross-vendor access.
-- See original migration for full auth context.

DROP POLICY IF EXISTS "anon_insert_vendor_subscriptions"   ON vendor_subscriptions;
CREATE POLICY "anon_insert_vendor_subscriptions"
  ON vendor_subscriptions FOR INSERT
  TO anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_vendor_subscriptions"   ON vendor_subscriptions;
CREATE POLICY "anon_update_vendor_subscriptions"
  ON vendor_subscriptions FOR UPDATE
  TO anon
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_insert_subscription_payments"  ON vendor_subscription_payments;
CREATE POLICY "anon_insert_subscription_payments"
  ON vendor_subscription_payments FOR INSERT
  TO anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_subscription_payments"  ON vendor_subscription_payments;
CREATE POLICY "anon_update_subscription_payments"
  ON vendor_subscription_payments FOR UPDATE
  TO anon
  USING (true) WITH CHECK (true);

-- ── 4a. Notify admin on new subscription purchase ─────────────────────────────

CREATE OR REPLACE FUNCTION fn_notify_subscription_purchased()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_vendor_name TEXT;
BEGIN
  IF NEW.status <> 'pending_payment' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'Unknown Vendor')
    INTO v_vendor_name
    FROM vendors WHERE id = NEW.vendor_id;

  INSERT INTO notifications
    (user_type, user_id, title, message, notification_type, is_read, created_at)
  SELECT
    'admin', au.id,
    'New Subscription Purchase',
    COALESCE(v_vendor_name, 'A vendor') || ' has initiated a subscription purchase.',
    'subscription_purchased',
    FALSE, NOW()
  FROM admin_users au
  WHERE au.is_active = TRUE;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_subscription_purchased ON vendor_subscriptions;
CREATE TRIGGER trg_notify_subscription_purchased
  AFTER INSERT ON vendor_subscriptions
  FOR EACH ROW EXECUTE FUNCTION fn_notify_subscription_purchased();

-- ── 4b. Notify vendor when subscription is activated ─────────────────────────

CREATE OR REPLACE FUNCTION fn_notify_subscription_activated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  IF NEW.status <> 'active' THEN RETURN NEW; END IF;

  INSERT INTO notifications
    (user_type, user_id, title, message, notification_type, is_read, created_at)
  VALUES (
    'vendor', NEW.vendor_id,
    'Subscription Activated',
    'Your subscription is now active. Enjoy your plan benefits!',
    'subscription_activated',
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_subscription_activated ON vendor_subscriptions;
CREATE TRIGGER trg_notify_subscription_activated
  AFTER UPDATE OF status ON vendor_subscriptions
  FOR EACH ROW EXECUTE FUNCTION fn_notify_subscription_activated();

-- ── 4c. Notify vendor when payment status changes ────────────────────────────

CREATE OR REPLACE FUNCTION fn_notify_subscription_payment_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;

  IF NEW.status = 'paid' THEN
    INSERT INTO notifications
      (user_type, user_id, title, message, notification_type, is_read, created_at)
    VALUES (
      'vendor', NEW.vendor_id,
      'Payment Successful',
      'Your subscription payment of ₹' ||
        TO_CHAR(NEW.amount, 'FM9999999990.00') || ' was successful.',
      'subscription_payment_paid',
      FALSE, NOW()
    );
  END IF;

  IF NEW.status = 'failed' THEN
    INSERT INTO notifications
      (user_type, user_id, title, message, notification_type, is_read, created_at)
    VALUES (
      'vendor', NEW.vendor_id,
      'Payment Failed',
      'Your subscription payment of ₹' ||
        TO_CHAR(NEW.amount, 'FM9999999990.00') ||
        ' failed. Please try again.',
      'subscription_payment_failed',
      FALSE, NOW()
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_subscription_payment_changed ON vendor_subscription_payments;
CREATE TRIGGER trg_notify_subscription_payment_changed
  AFTER UPDATE OF status ON vendor_subscription_payments
  FOR EACH ROW EXECUTE FUNCTION fn_notify_subscription_payment_changed();
