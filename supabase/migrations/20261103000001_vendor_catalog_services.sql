-- ── Vendor Catalog Services ───────────────────────────────────────────────────
--
-- Adds the infrastructure for Vendor Catalog Services: a discovery experience
-- where customers browse vendor-created custom services by category (Zomato-style).
--
-- Builds on the EXISTING vendor_service_requests table — no parallel system.
--
-- Changes:
--  1. Add catalog_node_id to vendor_service_requests (category association)
--  2. Add pricing_type / price_per_minute / duration_minutes to vendor_service_requests
--  3. Add vendor_pricing_snapshot JSONB to booking_items (immutable at booking time)
--  4. Insert vendor_catalog_enabled = 'false' into settings
--  5. Index on (catalog_node_id, status, is_active) for discovery queries
--  6. RPC get_vcs_categories()       — category tiles for home section
--  7. RPC get_vcs_vendors()          — vendor list for a category (+ optional location filter)
--  8. RPC get_vendor_vcs()           — vendor detail: services grouped by category
--  9. Replace search_vendor_custom_services to return new fields
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. vendor_service_requests — catalog association ─────────────────────────

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS catalog_node_id UUID
    REFERENCES catalog_nodes(id) ON DELETE SET NULL;

-- ── 2. vendor_service_requests — pricing type ────────────────────────────────

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS pricing_type TEXT NOT NULL DEFAULT 'fixed'
    CHECK (pricing_type IN ('fixed', 'minutes_based'));

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS price_per_minute NUMERIC(10,2);

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS duration_minutes INTEGER;

-- ── 3. booking_items — immutable pricing snapshot ────────────────────────────

ALTER TABLE booking_items
  ADD COLUMN IF NOT EXISTS vendor_pricing_snapshot JSONB;

-- ── 4. Settings key ───────────────────────────────────────────────────────────

INSERT INTO settings (setting_key, setting_value)
VALUES ('vendor_catalog_enabled', 'false')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 5. Index for discovery queries ───────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_vsr_catalog_discovery
  ON vendor_service_requests (catalog_node_id, status, is_active)
  WHERE request_type = 'new_service'
    AND status = 'completed'
    AND is_active = true;

-- ── 6. RPC: get_vcs_categories ───────────────────────────────────────────────
-- Returns catalog nodes that have at least one active vendor custom service,
-- together with how many distinct vendors offer services in each category.
-- Used for the home-section category-tile grid.

DROP FUNCTION IF EXISTS get_vcs_categories();

CREATE FUNCTION get_vcs_categories()
RETURNS TABLE (
  id           UUID,
  name         TEXT,
  slug         TEXT,
  icon_key     TEXT,
  image_url    TEXT,
  sort_order   INTEGER,
  vendor_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    cn.id,
    cn.name,
    cn.slug,
    cn.icon_key,
    cn.image_url,
    cn.sort_order,
    COUNT(DISTINCT vsr.vendor_id) AS vendor_count
  FROM catalog_nodes cn
  JOIN vendor_service_requests vsr ON vsr.catalog_node_id = cn.id
  JOIN vendors v                   ON v.id               = vsr.vendor_id
  WHERE cn.is_active  = true
    AND vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND v.is_active      = true
  GROUP BY cn.id, cn.name, cn.slug, cn.icon_key, cn.image_url, cn.sort_order
  ORDER BY cn.sort_order ASC, cn.name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_vcs_categories() TO anon, authenticated;

-- ── 7. RPC: get_vcs_vendors ───────────────────────────────────────────────────
-- Returns vendors who have ≥1 active custom service for p_category_id.
-- If p_lat / p_lng are supplied, only returns vendors whose serving areas cover
-- that coordinate (Haversine check, same formula used in preferred-vendor RPCs).
-- If no coordinates, all active vendors for that category are returned.

DROP FUNCTION IF EXISTS get_vcs_vendors(UUID, FLOAT8, FLOAT8);

CREATE FUNCTION get_vcs_vendors(
  p_category_id UUID,
  p_lat         FLOAT8 DEFAULT NULL,
  p_lng         FLOAT8 DEFAULT NULL
)
RETURNS TABLE (
  id                UUID,
  business_name     TEXT,
  rating            NUMERIC,
  profile_image_url TEXT,
  is_online         BOOLEAN,
  service_count     BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    v.id,
    v.business_name,
    v.rating::NUMERIC    AS rating,
    v.profile_image_url,
    v.is_online,
    COUNT(DISTINCT vsr.id) AS service_count
  FROM vendors v
  JOIN vendor_service_requests vsr ON vsr.vendor_id = v.id
  WHERE vsr.catalog_node_id = p_category_id
    AND vsr.request_type    = 'new_service'
    AND vsr.status          = 'completed'
    AND vsr.is_active       = true
    AND v.is_active         = true
    AND (
      -- Skip location filter when coordinates are not provided
      p_lat IS NULL
      OR p_lng IS NULL
      OR EXISTS (
        SELECT 1
        FROM vendor_serving_area_assignments vsaa
        JOIN vendor_serving_areas vsa ON vsa.id = vsaa.serving_area_id
        WHERE vsaa.vendor_id = v.id
          AND vsa.is_active  = true
          AND (
            2.0 * 6371.0 * asin(sqrt(
              power(sin(radians((vsa.latitude  - p_lat) / 2.0)), 2) +
              cos(radians(p_lat)) * cos(radians(vsa.latitude)) *
              power(sin(radians((vsa.longitude - p_lng) / 2.0)), 2)
            ))
          ) <= vsa.radius_km
      )
    )
  GROUP BY v.id, v.business_name, v.rating, v.profile_image_url, v.is_online
  ORDER BY v.rating DESC NULLS LAST, v.business_name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_vcs_vendors(UUID, FLOAT8, FLOAT8) TO anon, authenticated;

-- ── 8. RPC: get_vendor_vcs ────────────────────────────────────────────────────
-- Returns all active custom services for a vendor.
-- If p_category_id is supplied, filters to that category only.
-- Includes category info so the UI can group services by category.
-- Used by the Vendor Detail page.

DROP FUNCTION IF EXISTS get_vendor_vcs(UUID, UUID);

CREATE FUNCTION get_vendor_vcs(
  p_vendor_id   UUID,
  p_category_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id                 UUID,
  service_name       TEXT,
  description        TEXT,
  active_price       NUMERIC,
  image_url          TEXT,
  pricing_type       TEXT,
  price_per_minute   NUMERIC,
  duration_minutes   INTEGER,
  catalog_node_id    UUID,
  category_name      TEXT,
  category_icon_key  TEXT,
  rating             NUMERIC,
  review_count       INTEGER,
  included_items     JSONB,
  excluded_items     JSONB,
  before_after_pairs JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    vsr.id,
    vsr.service_name,
    vsr.description,
    vsr.active_price,
    vsr.image_url,
    vsr.pricing_type,
    vsr.price_per_minute,
    vsr.duration_minutes,
    vsr.catalog_node_id,
    cn.name        AS category_name,
    cn.icon_key    AS category_icon_key,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs
  FROM vendor_service_requests vsr
  LEFT JOIN catalog_nodes cn ON cn.id = vsr.catalog_node_id
  WHERE vsr.vendor_id     = p_vendor_id
    AND vsr.request_type  = 'new_service'
    AND vsr.status        = 'completed'
    AND vsr.is_active     = true
    AND (p_category_id IS NULL OR vsr.catalog_node_id = p_category_id)
  ORDER BY cn.sort_order ASC NULLS LAST, cn.name ASC NULLS LAST, vsr.service_name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_vendor_vcs(UUID, UUID) TO anon, authenticated;

-- ── 9. Update search_vendor_custom_services to return new fields ──────────────
-- Adds catalog_node_id, pricing_type, price_per_minute, duration_minutes
-- so the search results page can display the correct pricing breakdown.

DROP FUNCTION IF EXISTS search_vendor_custom_services(TEXT);

CREATE FUNCTION search_vendor_custom_services(p_query TEXT)
RETURNS TABLE (
  id                 UUID,
  service_name       TEXT,
  description        TEXT,
  active_price       NUMERIC,
  image_url          TEXT,
  vendor_id          UUID,
  vendor_name        TEXT,
  rating             NUMERIC,
  review_count       INTEGER,
  included_items     JSONB,
  excluded_items     JSONB,
  before_after_pairs JSONB,
  catalog_node_id    UUID,
  pricing_type       TEXT,
  price_per_minute   NUMERIC,
  duration_minutes   INTEGER
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    vsr.id,
    vsr.service_name,
    vsr.description,
    vsr.active_price,
    vsr.image_url,
    vsr.vendor_id,
    v.business_name     AS vendor_name,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs,
    vsr.catalog_node_id,
    vsr.pricing_type,
    vsr.price_per_minute,
    vsr.duration_minutes
  FROM vendor_service_requests vsr
  JOIN vendors v ON v.id = vsr.vendor_id
  WHERE vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND v.is_active      = true
    AND (
      vsr.service_name  ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY vsr.service_name
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION search_vendor_custom_services(TEXT) TO anon, authenticated;
