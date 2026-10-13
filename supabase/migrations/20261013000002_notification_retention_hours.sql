-- Switch notification retention from days to hours.
--
-- 1. Migrates existing notification_retention_days value → hours (×24).
--    Seeds 168 hrs (= 7 days) if neither key exists yet.
--    Drops the old _days key.
-- 2. Updates fn_purge_old_notifications() to read the new hours key.
-- 3. Updates admin_trigger_notification_purge() likewise.
-- 4. Changes the cron schedule from once-daily to once-hourly so sub-day
--    retention windows are enforced within one hour of expiry.

-- ── 1. Migrate / seed the setting key ────────────────────────────────────────

-- Convert existing days value → hours (only runs if the days key is present).
INSERT INTO settings (setting_key, setting_value)
SELECT 'notification_retention_hours',
       (COALESCE(NULLIF(TRIM(setting_value), ''), '7')::INT * 24)::TEXT
FROM   settings
WHERE  setting_key = 'notification_retention_days'
ON CONFLICT (setting_key) DO NOTHING;

-- Seed default 168 hrs if still missing (migration 20261013000001 was never applied).
INSERT INTO settings (setting_key, setting_value)
VALUES ('notification_retention_hours', '168')
ON CONFLICT (setting_key) DO NOTHING;

-- Remove the old key.
DELETE FROM settings WHERE setting_key = 'notification_retention_days';

-- ── 2. Fix fn_purge_old_notifications ────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_purge_old_notifications()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
  v_hours     INT;
  v_cutoff    TIMESTAMPTZ;
  v_notif_cnt INT := 0;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(setting_value), ''), '168')::INT
  INTO   v_hours
  FROM   settings
  WHERE  setting_key = 'notification_retention_hours';

  v_hours  := COALESCE(v_hours, 168);
  v_cutoff := NOW() - (v_hours || ' hours')::INTERVAL;

  DELETE FROM notifications WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_notif_cnt = ROW_COUNT;

  RAISE LOG '[DODO][Retention] Purged % notification rows older than % hours (cutoff=%)',
    v_notif_cnt, v_hours, v_cutoff;
END;
$func$;

-- ── 3. Update admin_trigger_notification_purge ────────────────────────────────

CREATE OR REPLACE FUNCTION admin_trigger_notification_purge()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hours     INT;
  v_cutoff    TIMESTAMPTZ;
  v_notif_cnt INT := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT COALESCE(NULLIF(TRIM(setting_value), ''), '168')::INT
  INTO   v_hours
  FROM   settings
  WHERE  setting_key = 'notification_retention_hours';

  v_hours  := COALESCE(v_hours, 168);
  v_cutoff := NOW() - (v_hours || ' hours')::INTERVAL;

  DELETE FROM notifications WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_notif_cnt = ROW_COUNT;

  RAISE LOG '[DODO][Retention] Admin manual purge: deleted % notification rows (cutoff=%, hours=%)',
    v_notif_cnt, v_cutoff, v_hours;

  RETURN json_build_object(
    'notifications_deleted', v_notif_cnt,
    'retention_hours',       v_hours,
    'cutoff',                v_cutoff
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_trigger_notification_purge() TO authenticated;

-- ── 4. Update cron schedule to hourly ────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $do$
BEGIN
  -- Drop and recreate to update the schedule expression.
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-old-notifications') THEN
    PERFORM cron.unschedule('purge-old-notifications');
  END IF;
  PERFORM cron.schedule(
    'purge-old-notifications',
    '0 * * * *',
    'SELECT fn_purge_old_notifications()'
  );
  RAISE LOG '[DODO][Retention] pg_cron job updated to hourly schedule.';
END;
$do$;
