-- Migration: configurable notification retention cleanup.
--
-- Adds notification_retention_days to the settings table (default 7), creates
-- fn_purge_old_notifications() that reads the setting at runtime, and registers
-- a daily pg_cron job that calls it.
--
-- Admin can change the retention period via Settings → Notification Settings
-- in the admin panel without any deployment.
--
-- pg_cron is already enabled (see 20260911000006_amc_expiry_cron.sql).

-- ── 1. Seed default retention setting ────────────────────────────────────────

INSERT INTO settings (setting_key, setting_value)
VALUES ('notification_retention_days', '7')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 2. Purge function ─────────────────────────────────────────────────────────
-- Reads notification_retention_days from settings at call time so changes
-- in the admin panel take effect on the next scheduled run.

CREATE OR REPLACE FUNCTION fn_purge_old_notifications()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
  v_days INT;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(setting_value), ''), '7')::INT
  INTO   v_days
  FROM   settings
  WHERE  setting_key = 'notification_retention_days';

  v_days := COALESCE(v_days, 7);

  DELETE FROM push_deliveries
  WHERE created_at < NOW() - (v_days || ' days')::INTERVAL;

  DELETE FROM notifications
  WHERE created_at < NOW() - (v_days || ' days')::INTERVAL;

  RAISE LOG '[DODO][Retention] Purged notifications and push_deliveries older than % days.', v_days;
END;
$func$;

-- ── 3. Register pg_cron job ───────────────────────────────────────────────────
-- Single job calls the function; both tables are handled inside it.
-- Uses a named dollar-quote tag ($do$) to avoid conflicting with the outer
-- DO block's $$ delimiter (which caused the syntax error in the first attempt).

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'purge-old-notifications'
  ) THEN
    PERFORM cron.schedule(
      'purge-old-notifications',
      '0 3 * * *',
      'SELECT fn_purge_old_notifications()'
    );
    RAISE LOG '[DODO][Retention] pg_cron job purge-old-notifications registered.';
  END IF;
END;
$do$;
