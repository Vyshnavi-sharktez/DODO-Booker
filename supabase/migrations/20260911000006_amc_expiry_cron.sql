-- ── AMC Expiry Cron ───────────────────────────────────────────────────────────
--
-- Schedules expire_overdue_amc_contracts() to run automatically every day at
-- 02:00 UTC via pg_cron, removing the dependency on a customer opening the app.
--
-- The customer-triggered sweep (amc_plans_provider.dart line 114) is kept as-is
-- so the UI reflects fresh state immediately on tab load. This cron job is the
-- second line of defence that covers contracts that would otherwise stay stale
-- in the DB (e.g. customers who haven't opened the app for days).
--
-- Why 02:00 UTC:
--   Low-traffic window; avoids clock-tick boundary noise at 00:00 UTC.
--
-- Idempotent: the DO block only schedules the job if it doesn't already exist,
-- so re-running this migration is safe.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'expire-overdue-amc-contracts'
  ) THEN
    PERFORM cron.schedule(
      'expire-overdue-amc-contracts',
      '0 2 * * *',
      'SELECT public.expire_overdue_amc_contracts()'
    );
  END IF;
END;
$$;
