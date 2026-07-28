-- ── Catalog-Specific Vendor Subscriptions ──────────────────────────────────────
--
-- Extends vendor_subscriptions to support per-catalog-node subscriptions alongside
-- the existing global subscription.
--
-- Changes:
--   1. Make plan_id nullable (catalog subs have no subscription_plans row)
--   2. Add catalog_node_id — identifies which catalog node this sub belongs to;
--      NULL = global subscription (existing behaviour)
--   3. Add subscription_permissions — JSONB snapshot of permissions at purchase
--      time for catalog subs (global subs read permissions via plan FK join)
--   4. CHECK: exactly one of (plan_id, catalog_node_id) must be set
--   5. Rebuild unique active-subscription index per scope:
--        - Global: one active per vendor (catalog_node_id IS NULL)
--        - Catalog: one active per (vendor, catalog_node)
--   6. Update check_vendor_cod_eligibility to recognise catalog subscriptions
--   7. Add get_catalog_vendor_subscription_offerings() RPC — returns all catalog
--      nodes that have vendor_subscription module enabled in catalog_node_configs
--
-- Safe to re-run: IF NOT EXISTS / CREATE OR REPLACE / DO $$ throughout.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Make plan_id nullable ──────────────────────────────────────────────────

ALTER TABLE vendor_subscriptions ALTER COLUMN plan_id DROP NOT NULL;

-- ── 2. Add catalog_node_id ────────────────────────────────────────────────────

ALTER TABLE vendor_subscriptions
  ADD COLUMN IF NOT EXISTS catalog_node_id UUID REFERENCES catalog_nodes(id) ON DELETE RESTRICT;

-- ── 3. Add subscription_permissions snapshot ──────────────────────────────────
-- Stores a copy of the plan's permissions JSONB at purchase time so COD checks
-- and admin views don't need to re-query catalog_node_configs after the fact.

ALTER TABLE vendor_subscriptions
  ADD COLUMN IF NOT EXISTS subscription_permissions JSONB;

-- ── 4. Scope check — exactly one of plan_id / catalog_node_id ────────────────

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'vendor_subscriptions'
      AND constraint_name = 'vs_scope_check'
  ) THEN
    ALTER TABLE vendor_subscriptions
      ADD CONSTRAINT vs_scope_check
      CHECK (
        (plan_id IS NOT NULL AND catalog_node_id IS NULL)
        OR
        (plan_id IS NULL AND catalog_node_id IS NOT NULL)
      );
  END IF;
END $$;

-- ── 5. Rebuild unique active-subscription index ───────────────────────────────
-- The old index blocks a single vendor from having two open subscriptions of any
-- kind.  The new pair of indexes enforce the correct per-scope rule:
--   • Global  → one open record per vendor  (catalog_node_id IS NULL)
--   • Catalog → one open record per (vendor, catalog node)

DROP INDEX IF EXISTS uq_vendor_subscriptions_active;

CREATE UNIQUE INDEX IF NOT EXISTS uq_vs_global_active
  ON vendor_subscriptions(vendor_id)
  WHERE catalog_node_id IS NULL
    AND status IN ('active', 'pending', 'pending_payment', 'pending_approval');

CREATE UNIQUE INDEX IF NOT EXISTS uq_vs_catalog_active
  ON vendor_subscriptions(vendor_id, catalog_node_id)
  WHERE catalog_node_id IS NOT NULL
    AND status IN ('active', 'pending', 'pending_payment', 'pending_approval');

-- ── 6. Update COD eligibility check ──────────────────────────────────────────
-- Unchanged logic for global subscriptions; adds a fallback that grants COD
-- access when the vendor has any active catalog subscription with allow_cod=true.
-- Fine-grained per-catalog COD checks (matching booking.service_id to a specific
-- catalog_node) are tracked for a future enhancement.

CREATE OR REPLACE FUNCTION check_vendor_cod_eligibility(p_vendor_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_subscription_enabled TEXT;
  v_require_subscription  TEXT;
  v_allow_free_vendors    TEXT;
  v_is_active             BOOLEAN;
  v_allow_cod             BOOLEAN;
BEGIN
  SELECT setting_value INTO v_subscription_enabled
    FROM settings WHERE setting_key = 'subscription_enabled';
  v_subscription_enabled := COALESCE(v_subscription_enabled, 'false');

  SELECT is_active INTO v_is_active FROM vendors WHERE id = p_vendor_id;
  IF NOT FOUND OR NOT v_is_active THEN RETURN FALSE; END IF;

  IF v_subscription_enabled <> 'true' THEN RETURN TRUE; END IF;

  SELECT setting_value INTO v_require_subscription
    FROM settings WHERE setting_key = 'subscription_require_active';
  v_require_subscription := COALESCE(v_require_subscription, 'false');

  SELECT setting_value INTO v_allow_free_vendors
    FROM settings WHERE setting_key = 'subscription_allow_free_vendors';
  v_allow_free_vendors := COALESCE(v_allow_free_vendors, 'true');

  IF v_require_subscription <> 'true' THEN RETURN TRUE; END IF;

  -- Check global subscription (plan_id IS NOT NULL join with subscription_plans)
  SELECT (sp.permissions->>'allow_cod')::BOOLEAN
    INTO v_allow_cod
    FROM vendor_subscriptions vs
    JOIN subscription_plans sp ON sp.id = vs.plan_id
   WHERE vs.vendor_id = p_vendor_id
     AND vs.catalog_node_id IS NULL
     AND vs.status = 'active'
   LIMIT 1;

  IF FOUND THEN
    RETURN COALESCE(v_allow_cod, FALSE);
  END IF;

  -- Check catalog subscriptions (permissions stored inline as snapshot)
  PERFORM 1
    FROM vendor_subscriptions vs
   WHERE vs.vendor_id = p_vendor_id
     AND vs.catalog_node_id IS NOT NULL
     AND vs.status = 'active'
     AND (vs.subscription_permissions->>'allow_cod')::BOOLEAN = TRUE
   LIMIT 1;

  IF FOUND THEN RETURN TRUE; END IF;

  -- No active subscription of any kind
  RETURN v_allow_free_vendors = 'true';
END;
$$;

-- ── 7. RPC: catalog subscription offerings ────────────────────────────────────
-- Returns all catalog nodes that currently have the vendor_subscription module
-- enabled.  The vendor app calls this to render the "Catalog Plans" section on
-- the Browse Plans screen.  SECURITY DEFINER so the anon role can read
-- catalog_node_configs without an explicit RLS policy change.

CREATE OR REPLACE FUNCTION get_catalog_vendor_subscription_offerings()
RETURNS TABLE (
  config_id UUID,
  node_id   UUID,
  node_name TEXT,
  node_slug TEXT,
  config    JSONB
)
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    cnc.id       AS config_id,
    cn.id        AS node_id,
    cn.name      AS node_name,
    cn.slug      AS node_slug,
    cnc.config   AS config
  FROM catalog_node_configs cnc
  JOIN catalog_nodes cn ON cn.id = cnc.node_id
  WHERE cnc.module     = 'vendor_subscription'
    AND cnc.is_enabled = TRUE
    AND (cnc.config->>'is_enabled')::BOOLEAN = TRUE
    AND (cnc.config->>'is_active')::BOOLEAN  = TRUE
    AND cn.is_active   = TRUE
    AND cnc.relationship_id IS NULL
  ORDER BY cn.name;
$$;

GRANT EXECUTE ON FUNCTION get_catalog_vendor_subscription_offerings() TO anon, authenticated;
