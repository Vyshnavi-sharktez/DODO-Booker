-- ═══════════════════════════════════════════════════════════════════════════════
-- AMC Plans Module
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── amc_plans ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.amc_plans (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_name              text NOT NULL,
  -- 'monthly' | 'quarterly' | 'half_yearly' | 'yearly' | 'custom'
  package_duration       text NOT NULL DEFAULT 'yearly',
  -- Only for 'custom': exact number of days in the contract period
  package_duration_value integer,
  -- 'weekly' | 'bi_weekly' | 'monthly' | 'custom'
  service_interval       text NOT NULL DEFAULT 'monthly',
  -- Only for 'custom': exact number of days between visits
  service_interval_value integer,
  price_per_visit        numeric(12,2) NOT NULL DEFAULT 0,
  -- 'percentage' | 'fixed'
  discount_type          text NOT NULL DEFAULT 'percentage',
  discount_value         numeric(12,2) NOT NULL DEFAULT 0,
  is_active              boolean NOT NULL DEFAULT true,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

-- ── catalog_node_amc_plans ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.catalog_node_amc_plans (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  node_id     uuid NOT NULL REFERENCES public.catalog_nodes(id) ON DELETE CASCADE,
  amc_plan_id uuid NOT NULL REFERENCES public.amc_plans(id) ON DELETE CASCADE,
  sort_order  integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (node_id, amc_plan_id)
);

CREATE INDEX IF NOT EXISTS idx_catalog_node_amc_plans_node
  ON public.catalog_node_amc_plans(node_id);

CREATE INDEX IF NOT EXISTS idx_catalog_node_amc_plans_plan
  ON public.catalog_node_amc_plans(amc_plan_id);

-- ── Extend amc_contracts ────────────────────────────────────────────────────────
-- These columns store a complete pricing snapshot locked at purchase time.
ALTER TABLE public.amc_contracts
  ADD COLUMN IF NOT EXISTS amc_plan_id      uuid REFERENCES public.amc_plans(id),
  ADD COLUMN IF NOT EXISTS package_duration text,
  ADD COLUMN IF NOT EXISTS service_interval text,
  ADD COLUMN IF NOT EXISTS num_visits       integer,
  ADD COLUMN IF NOT EXISTS original_total   numeric(12,2),
  ADD COLUMN IF NOT EXISTS discount_type    text,
  ADD COLUMN IF NOT EXISTS discount_value   numeric(12,2),
  ADD COLUMN IF NOT EXISTS discount_amount  numeric(12,2),
  ADD COLUMN IF NOT EXISTS final_price      numeric(12,2);

-- ── RLS ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.amc_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_node_amc_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "amc_plans_all" ON public.amc_plans;
DROP POLICY IF EXISTS "catalog_node_amc_plans_all" ON public.catalog_node_amc_plans;

-- Full access for authenticated users (admin panel uses service role; customer app
-- authenticated users need read access for the plan catalogue).
CREATE POLICY "amc_plans_all" ON public.amc_plans
  FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "catalog_node_amc_plans_all" ON public.catalog_node_amc_plans
  FOR ALL USING (true) WITH CHECK (true);
