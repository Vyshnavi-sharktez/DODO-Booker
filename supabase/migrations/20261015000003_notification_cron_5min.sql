-- Change notification cleanup cron from top-of-hour to every-5-minutes.
-- Unschedules the existing job and recreates it with the new schedule.
-- Retention logic and fn_purge_old_notifications() are unchanged.

DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-old-notifications') THEN
    PERFORM cron.unschedule('purge-old-notifications');
  END IF;
  PERFORM cron.schedule(
    'purge-old-notifications',
    '*/5 * * * *',
    'SELECT fn_purge_old_notifications()'
  );
  RAISE LOG '[DODO][Retention] pg_cron schedule updated to every-5-minutes.';
END;
$do$;
