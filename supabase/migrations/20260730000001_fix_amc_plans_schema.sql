-- ── Fix amc_plans schema mismatch ────────────────────────────────────────────
-- amc_plans was created by 20260728000003_amc_phase1.sql with a different
-- column set (name, recurrence, num_visits, service_id, stored generated
-- columns). 20260729_amc_plans.sql's CREATE TABLE IF NOT EXISTS was a no-op
-- because the table already existed, leaving the new columns unwritten.
--
-- This migration adds only the columns the Flutter implementation expects.
-- No existing columns are dropped; no existing data is lost.

-- 1. plan_name  (old schema used 'name' which still exists and is NOT NULL)
ALTER TABLE public.amc_plans
  ADD COLUMN IF NOT EXISTS plan_name text NOT NULL DEFAULT '';

-- Back-fill from the old 'name' column for any pre-existing rows.
UPDATE public.amc_plans
  SET plan_name = name
  WHERE plan_name = '';

-- 2. package_duration  ('monthly'|'quarterly'|'half_yearly'|'yearly'|'custom')
ALTER TABLE public.amc_plans
  ADD COLUMN IF NOT EXISTS package_duration text NOT NULL DEFAULT 'yearly';

-- 3. package_duration_value  (number of days; only used when package_duration = 'custom')
ALTER TABLE public.amc_plans
  ADD COLUMN IF NOT EXISTS package_duration_value integer;

-- 4. service_interval  ('weekly'|'bi_weekly'|'monthly'|'custom')
--    Old schema had 'recurrence' with values 'weekly'|'monthly'|'yearly'.
ALTER TABLE public.amc_plans
  ADD COLUMN IF NOT EXISTS service_interval text NOT NULL DEFAULT 'monthly';

-- Back-fill from 'recurrence' where values are directly compatible.
UPDATE public.amc_plans
  SET service_interval = recurrence
  WHERE service_interval = 'monthly'
    AND recurrence IN ('weekly', 'monthly');

-- 5. service_interval_value  (number of days; only used when service_interval = 'custom')
ALTER TABLE public.amc_plans
  ADD COLUMN IF NOT EXISTS service_interval_value integer;
