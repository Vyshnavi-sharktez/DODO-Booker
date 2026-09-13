-- ── Warranty Expiry Cron ──────────────────────────────────────────────────────
--
-- Schedules process_expired_service_warranties() to run automatically every day
-- at 02:30 UTC via pg_cron so DB `status` stays in sync with `expires_at`.
--
-- Without this, a warranty whose `expires_at` has passed keeps `status = 'Active'`
-- in the DB indefinitely. Client-side `isExpired` getters still work correctly
-- (they check `expires_at` directly), but admin analytics queries and exports
-- that filter on `status = 'Expired'` return wrong counts.
--
-- Runs at 02:30 UTC — 30 min after the AMC sweep (02:00 UTC) to avoid
-- resource contention on the same nightly window.
--
-- Idempotent: the DO block only schedules the job if it doesn't already exist,
-- so re-running this migration is safe.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'expire-overdue-warranties'
  ) THEN
    PERFORM cron.schedule(
      'expire-overdue-warranties',
      '30 2 * * *',
      'SELECT public.process_expired_service_warranties()'
    );
  END IF;
END;
$$;
