-- ── Vendor Subscriptions — Enforcement & Automation ──────────────────────────
--
-- Depends on: 20260727000001_vendor_subscriptions.sql
--
-- Adds:
--   1. reminder_sent_at column to vendor_subscriptions
--   2. Settings seed for all subscription keys (idempotent)
--   3. fn_enforce_cod_vendor_eligibility() + trigger on bookings
--         → Blocks INSERT/UPDATE when a COD booking is assigned to an
--           ineligible vendor (respects the subscription_enabled master switch)
--   4. fn_expire_vendor_subscriptions()
--         → Transitions active → expired after expiry_date + grace period;
--           inserts a vendor notification for each expiry.
--           Call daily via pg_cron or a Supabase Edge Function.
--   5. fn_send_subscription_reminders()
--         → Sends a pre-expiry reminder N days before expiry (N from settings).
--           Uses reminder_sent_at to avoid duplicate sends.
--           Call daily via pg_cron or a Supabase Edge Function.
--   6. pg_cron schedules (guarded — no-op if extension unavailable)
--
-- Safe to re-run: CREATE OR REPLACE, IF NOT EXISTS, ON CONFLICT throughout.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Reminder tracking column ───────────────────────────────────────────────

ALTER TABLE vendor_subscriptions
  ADD COLUMN IF NOT EXISTS reminder_sent_at TIMESTAMPTZ;

-- ── 2. Settings seed ──────────────────────────────────────────────────────────

INSERT INTO settings (setting_key, setting_value) VALUES
  ('subscription_enabled',               'false'),
  ('subscription_require_active',        'false'),
  ('subscription_allow_free_vendors',    'true'),
  ('subscription_grace_period_days',     '3'),
  ('subscription_reminder_days',         '7'),
  ('subscription_auto_disable_cod',      'false'),
  ('subscription_auto_disable_assignment', 'false')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 3. COD eligibility enforcement on bookings ────────────────────────────────
--
-- Fires BEFORE INSERT (all rows) and BEFORE UPDATE (only when vendor_id or
-- payment_method is included in the UPDATE statement).
--
-- Passes through when:
--   - vendor_id IS NULL (booking not yet assigned)
--   - payment_method ≠ 'cod'
--   - subscription module is disabled (check_vendor_cod_eligibility returns TRUE)
--   - both vendor_id and payment_method are unchanged on UPDATE
--
-- Raises SQLSTATE P0001 when the vendor cannot accept COD bookings so that
-- Supabase/PostgREST surfaces a clear error to the calling client.

CREATE OR REPLACE FUNCTION fn_enforce_cod_vendor_eligibility()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- No vendor yet or payment is not COD — nothing to check.
  IF NEW.vendor_id IS NULL
   OR LOWER(COALESCE(NEW.payment_method, '')) NOT IN ('cash', 'cod') THEN
    RETURN NEW;
  END IF;

  -- UPDATE: skip when neither relevant column actually changed value.
  IF TG_OP = 'UPDATE'
     AND OLD.vendor_id      IS NOT DISTINCT FROM NEW.vendor_id
     AND OLD.payment_method IS NOT DISTINCT FROM NEW.payment_method THEN
    RETURN NEW;
  END IF;

  -- check_vendor_cod_eligibility handles the subscription_enabled gate;
  -- when the module is off it always returns TRUE.
  IF NOT check_vendor_cod_eligibility(NEW.vendor_id) THEN
    RAISE EXCEPTION
      'Vendor % is not eligible to accept COD bookings. '
      'Verify that the vendor has an active subscription and that the '
      'plan includes COD permission.',
      NEW.vendor_id
    USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_cod_vendor_eligibility ON bookings;
CREATE TRIGGER trg_enforce_cod_vendor_eligibility
  BEFORE INSERT OR UPDATE OF vendor_id, payment_method ON bookings
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_cod_vendor_eligibility();

-- ── 4. fn_expire_vendor_subscriptions() ──────────────────────────────────────
--
-- Reads subscription_grace_period_days from settings (default 0).
-- Marks subscriptions expired when:
--   status = 'active'  AND  expiry_date + grace_period < NOW()
--
-- Inserts a 'vendor' notification for each expired subscription so the vendor
-- app's realtime channel picks it up automatically.
--
-- Returns: number of subscriptions expired in this run.

CREATE OR REPLACE FUNCTION fn_expire_vendor_subscriptions()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grace_setting TEXT;
  v_grace_days    INT;
  v_cutoff        TIMESTAMPTZ;
  v_expired_count INT := 0;
  v_rec           RECORD;
BEGIN
  SELECT setting_value INTO v_grace_setting
    FROM settings WHERE setting_key = 'subscription_grace_period_days';
  v_grace_days := COALESCE(v_grace_setting::INT, 0);

  -- Subscriptions are eligible for expiry after expiry_date + grace_period.
  v_cutoff := NOW() - (v_grace_days || ' days')::INTERVAL;

  FOR v_rec IN
    UPDATE vendor_subscriptions
       SET status = 'expired'
     WHERE status    = 'active'
       AND expiry_date IS NOT NULL
       AND expiry_date < v_cutoff
     RETURNING id, vendor_id
  LOOP
    v_expired_count := v_expired_count + 1;

    -- Vendor notification — picked up by the vendor app realtime channel.
    INSERT INTO notifications
      (user_type, user_id, title, message, notification_type, is_read, created_at)
    VALUES (
      'vendor',
      v_rec.vendor_id,
      'Subscription Expired',
      'Your subscription has expired. Please contact the platform administrator to renew.',
      'subscription_expired',
      FALSE,
      NOW()
    );

    RAISE LOG '[DODO][Subscription] Expired: subscription_id=% vendor_id=%',
      v_rec.id, v_rec.vendor_id;
  END LOOP;

  RETURN v_expired_count;
END;
$$;

-- ── 5. fn_send_subscription_reminders() ──────────────────────────────────────
--
-- Reads subscription_reminder_days from settings (default 7).
-- Sends a reminder for every active subscription whose expiry_date falls
-- within [NOW(), NOW() + reminder_days].
--
-- reminder_sent_at is used as a per-subscription dedup guard: a reminder is
-- only sent if none was sent in the previous 23 hours.  This lets the cron
-- job run daily without sending repeated reminders.
--
-- Returns: number of reminders sent in this run.

CREATE OR REPLACE FUNCTION fn_send_subscription_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reminder_setting TEXT;
  v_reminder_days    INT;
  v_window_end       TIMESTAMPTZ;
  v_sent_count       INT := 0;
  v_rec              RECORD;
BEGIN
  SELECT setting_value INTO v_reminder_setting
    FROM settings WHERE setting_key = 'subscription_reminder_days';
  v_reminder_days := COALESCE(v_reminder_setting::INT, 7);
  v_window_end    := NOW() + (v_reminder_days || ' days')::INTERVAL;

  FOR v_rec IN
    SELECT id, vendor_id, expiry_date
      FROM vendor_subscriptions
     WHERE status       = 'active'
       AND expiry_date  IS NOT NULL
       AND expiry_date  BETWEEN NOW() AND v_window_end
       AND (
             reminder_sent_at IS NULL
          OR reminder_sent_at < NOW() - INTERVAL '23 hours'
           )
  LOOP
    -- Stamp the reminder time first so a crash loop cannot flood the vendor.
    UPDATE vendor_subscriptions
       SET reminder_sent_at = NOW()
     WHERE id = v_rec.id;

    INSERT INTO notifications
      (user_type, user_id, title, message, notification_type, is_read, created_at)
    VALUES (
      'vendor',
      v_rec.vendor_id,
      'Subscription Expiring Soon',
      'Your subscription expires on '
        || TO_CHAR(v_rec.expiry_date AT TIME ZONE 'UTC', 'DD Mon YYYY')
        || '. Renew now to avoid service interruptions.',
      'subscription_expiry_reminder',
      FALSE,
      NOW()
    );

    v_sent_count := v_sent_count + 1;
    RAISE LOG '[DODO][Subscription] Reminder sent: subscription_id=% vendor_id=% expiry=%',
      v_rec.id, v_rec.vendor_id, v_rec.expiry_date;
  END LOOP;

  RETURN v_sent_count;
END;
$$;

-- ── 6. pg_cron scheduling ─────────────────────────────────────────────────────
--
-- Registers daily cron jobs when pg_cron is available.
-- If pg_cron is not installed, this block completes without error and the
-- functions must be invoked via a Supabase Edge Function or external scheduler.
--
-- To enable pg_cron: Supabase Dashboard → Database → Extensions → pg_cron.
--
-- Schedule (UTC):
--   00:00 — expire overdue subscriptions
--   01:00 — send pre-expiry reminders

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE LOG '[DODO][Subscription] pg_cron not available — schedule jobs manually.';
    RETURN;
  END IF;

  -- Remove stale jobs before recreating (idempotent).
  DELETE FROM cron.job
   WHERE jobname IN ('expire-vendor-subscriptions', 'send-subscription-reminders');

  PERFORM cron.schedule(
    'expire-vendor-subscriptions',
    '0 0 * * *',
    'SELECT fn_expire_vendor_subscriptions()'
  );
  PERFORM cron.schedule(
    'send-subscription-reminders',
    '0 1 * * *',
    'SELECT fn_send_subscription_reminders()'
  );

  RAISE LOG '[DODO][Subscription] pg_cron jobs registered.';
EXCEPTION WHEN others THEN
  RAISE WARNING '[DODO][Subscription] pg_cron scheduling failed: %', SQLERRM;
END;
$$;
