-- Fix: fn_purge_old_notifications() referenced push_deliveries.created_at
-- which does not exist (the column is attempted_at).  That caused a runtime
-- error on every cron execution, so no notifications were ever deleted.
--
-- push_deliveries has REFERENCES notifications(id) ON DELETE CASCADE, so
-- deleting from notifications automatically removes the push_delivery rows.
-- The explicit push_deliveries DELETE is dropped entirely.
--
-- Also adds admin_trigger_notification_purge() so the admin panel can run an
-- immediate cleanup and see the deleted count without waiting for 3 AM.

-- ── 1. Fix fn_purge_old_notifications ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_purge_old_notifications()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
  v_days      INT;
  v_cutoff    TIMESTAMPTZ;
  v_notif_cnt INT := 0;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(setting_value), ''), '7')::INT
  INTO   v_days
  FROM   settings
  WHERE  setting_key = 'notification_retention_days';

  v_days   := COALESCE(v_days, 7);
  v_cutoff := NOW() - (v_days || ' days')::INTERVAL;

  -- push_deliveries references notifications(id) ON DELETE CASCADE,
  -- so this single DELETE handles both tables.
  DELETE FROM notifications
  WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_notif_cnt = ROW_COUNT;

  RAISE LOG '[DODO][Retention] Purged % notification rows older than % days (cutoff=%)',
    v_notif_cnt, v_days, v_cutoff;
END;
$func$;

-- ── 2. Ensure cron job exists (idempotent) ────────────────────────────────────

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

-- ── 3. Seed default if missing ────────────────────────────────────────────────

INSERT INTO settings (setting_key, setting_value)
VALUES ('notification_retention_days', '7')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 4. Admin-callable purge RPC ───────────────────────────────────────────────
-- Returns JSON: { notifications_deleted, retention_days, cutoff }
-- Requires an authenticated Supabase session.
-- push_deliveries rows are removed by cascade, not counted separately.

CREATE OR REPLACE FUNCTION admin_trigger_notification_purge()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days      INT;
  v_cutoff    TIMESTAMPTZ;
  v_notif_cnt INT := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT COALESCE(NULLIF(TRIM(setting_value), ''), '7')::INT
  INTO   v_days
  FROM   settings
  WHERE  setting_key = 'notification_retention_days';

  v_days   := COALESCE(v_days, 7);
  v_cutoff := NOW() - (v_days || ' days')::INTERVAL;

  DELETE FROM notifications
  WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_notif_cnt = ROW_COUNT;

  RAISE LOG '[DODO][Retention] Admin manual purge: deleted % notification rows (cutoff=%, days=%)',
    v_notif_cnt, v_cutoff, v_days;

  RETURN json_build_object(
    'notifications_deleted', v_notif_cnt,
    'retention_days',        v_days,
    'cutoff',                v_cutoff
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_trigger_notification_purge() TO authenticated;
