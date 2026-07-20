-- ── Preferred Vendors Catalog Module ─────────────────────────────────────────
-- Moves preferred-vendor configuration from the Surge Fee module into its own
-- first-class catalog module so it can be scoped per-service via the existing
-- catalog_node_configs resolver, just like Tax, Loyalty, Scheduling, etc.
--
-- 1. Extend the module CHECK constraint.
-- 2. Drop the now-redundant surge_fee_settings.preferred_vendor_fee_enabled.
-- 3. RPC for the customer app: resolve configured vendor IDs → filter by location.

-- ── 1. Module CHECK ───────────────────────────────────────────────────────────

ALTER TABLE catalog_node_configs
  DROP CONSTRAINT IF EXISTS catalog_node_configs_module_check;

ALTER TABLE catalog_node_configs
  ADD CONSTRAINT catalog_node_configs_module_check
  CHECK (module IN (
    'tax', 'loyalty', 'scheduling', 'commission', 'surge', 'preferred_vendors'
  ));

-- ── 2. Drop surge_fee_settings.preferred_vendor_fee_enabled ──────────────────
-- The feature is now controlled per catalog node; the global toggle is not needed.

ALTER TABLE surge_fee_settings
  DROP COLUMN IF EXISTS preferred_vendor_fee_enabled;

-- ── 3. RPC: preferred vendors by configured IDs that also serve a coordinate ──
-- Called by the customer app after resolving the preferred_vendors module config.
-- p_vendor_ids  – TEXT[] of vendor UUIDs stored in the catalog config JSONB.
-- p_lat / p_lng – customer address coordinates for serving-area proximity check.
-- SECURITY DEFINER so the anon role can call it without direct vendor RLS access.

CREATE OR REPLACE FUNCTION get_preferred_vendors_by_ids_and_location(
  p_vendor_ids TEXT[],
  p_lat        FLOAT8,
  p_lng        FLOAT8
)
RETURNS TABLE (
  id                   UUID,
  business_name        TEXT,
  rating               NUMERIC,
  preferred_vendor_fee NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT sub.id, sub.business_name, sub.rating, sub.preferred_vendor_fee
  FROM (
    SELECT DISTINCT
      v.id,
      v.business_name,
      v.rating::NUMERIC               AS rating,
      v.preferred_vendor_fee::NUMERIC AS preferred_vendor_fee
    FROM   vendors                         v
    JOIN   vendor_serving_area_assignments vsaa ON vsaa.vendor_id    = v.id
    JOIN   vendor_serving_areas            vsa  ON vsa.id            = vsaa.serving_area_id
    WHERE  v.id       = ANY(p_vendor_ids::UUID[])
      AND  v.is_active    = true
      AND  vsa.is_active  = true
      AND  (
        2.0 * 6371.0 * asin(sqrt(
          power(sin(radians((vsa.latitude  - p_lat)  / 2.0)), 2) +
          cos(radians(p_lat)) * cos(radians(vsa.latitude)) *
          power(sin(radians((vsa.longitude - p_lng) / 2.0)), 2)
        ))
      ) <= vsa.radius_km
  ) sub
  ORDER BY sub.rating DESC NULLS LAST, sub.business_name;
$$;
