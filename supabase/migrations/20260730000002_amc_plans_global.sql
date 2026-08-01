-- ── Make amc_plans global (decouple from service_id) ─────────────────────────
-- The old schema (20260728000003_amc_phase1.sql) tied each plan directly to a
-- single catalog_nodes row via service_id NOT NULL. The finalised design uses
-- catalog_node_amc_plans as the many-to-many join, making amc_plans global
-- entities that can be linked to any number of services.
--
-- Also unblocks Flutter INSERTs: three other old NOT NULL columns (name,
-- recurrence, num_visits) are not written by the current repository and must
-- be made nullable so new rows can be created.

-- 1. Preserve existing service_id relationships in the junction table.
--    ON CONFLICT DO NOTHING handles any rows already migrated.
INSERT INTO public.catalog_node_amc_plans (node_id, amc_plan_id, sort_order)
  SELECT service_id, id, 0
  FROM   public.amc_plans
  WHERE  service_id IS NOT NULL
ON CONFLICT (node_id, amc_plan_id) DO NOTHING;

-- 2. Remove the service_id column and its index.
DROP INDEX IF EXISTS public.idx_amc_plans_service_id;
ALTER TABLE public.amc_plans DROP COLUMN IF EXISTS service_id;

-- 3. Make the remaining old NOT NULL columns nullable.
--    The Flutter repository writes plan_name / service_interval instead;
--    these legacy columns are kept so existing row data is not lost.
ALTER TABLE public.amc_plans
  ALTER COLUMN name       DROP NOT NULL,
  ALTER COLUMN recurrence DROP NOT NULL,
  ALTER COLUMN num_visits DROP NOT NULL;
