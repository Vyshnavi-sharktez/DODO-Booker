-- ── Vendor-Owned Categories ───────────────────────────────────────────────────
--
-- Replaces the catalog_node_id → catalog_nodes association (added in
-- 20261103000001) with a fully vendor-owned category system.
-- Vendors manage their own categories; DODO's global catalog is not used.
--
-- Changes:
--  1. vendor_categories table — isolated per vendor, unique name within vendor
--  2. vendor_service_requests — swap catalog_node_id → vendor_category_id
--  3. RLS policies for vendor_categories
--  4. get_my_vendor_categories() RPC  — vendor's own categories + service counts
--  5. Recreate get_vcs_categories()   — now joins vendor_categories
--  6. Recreate get_vcs_vendors()      — filters on vendor_category_id
--  7. Recreate get_vendor_vcs()       — joins vendor_categories
--  8. Recreate search_vendor_custom_services() — uses vendor_category_id
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. vendor_categories ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS vendor_categories (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id  UUID        NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  name       TEXT        NOT NULL,
  icon_url   TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT vendor_categories_unique_name UNIQUE (vendor_id, name)
);

-- ── 2. vendor_service_requests — swap category reference ─────────────────────

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS vendor_category_id UUID
    REFERENCES vendor_categories(id) ON DELETE SET NULL;

-- Drop catalog_node_id (was added in 20261103000001; now replaced)
ALTER TABLE vendor_service_requests
  DROP COLUMN IF EXISTS catalog_node_id;

-- Replace discovery index
DROP INDEX IF EXISTS idx_vsr_catalog_discovery;

CREATE INDEX IF NOT EXISTS idx_vsr_vendor_category_discovery
  ON vendor_service_requests (vendor_category_id, status, is_active)
  WHERE request_type = 'new_service'
    AND status       = 'completed'
    AND is_active    = true;

-- ── 3. RLS — vendor_categories ───────────────────────────────────────────────

ALTER TABLE vendor_categories ENABLE ROW LEVEL SECURITY;

-- Public SELECT (customer discovery, admin views)
DROP POLICY IF EXISTS "vc_select_public" ON vendor_categories;
CREATE POLICY "vc_select_public" ON vendor_categories
  FOR SELECT USING (true);

-- Authenticated vendors: INSERT only for their own account
DROP POLICY IF EXISTS "vc_insert_vendor" ON vendor_categories;
CREATE POLICY "vc_insert_vendor" ON vendor_categories
  FOR INSERT TO authenticated
  WITH CHECK (
    vendor_id IN (
      SELECT id FROM vendors WHERE auth_user_id = auth.uid()
    )
  );

-- Authenticated vendors: UPDATE only their own categories
DROP POLICY IF EXISTS "vc_update_vendor" ON vendor_categories;
CREATE POLICY "vc_update_vendor" ON vendor_categories
  FOR UPDATE TO authenticated
  USING (
    vendor_id IN (SELECT id FROM vendors WHERE auth_user_id = auth.uid())
  )
  WITH CHECK (
    vendor_id IN (SELECT id FROM vendors WHERE auth_user_id = auth.uid())
  );

-- Authenticated vendors: DELETE only their own categories
DROP POLICY IF EXISTS "vc_delete_vendor" ON vendor_categories;
CREATE POLICY "vc_delete_vendor" ON vendor_categories
  FOR DELETE TO authenticated
  USING (
    vendor_id IN (SELECT id FROM vendors WHERE auth_user_id = auth.uid())
  );

-- ── 4. RPC: get_my_vendor_categories ─────────────────────────────────────────
-- Returns the calling authenticated vendor's categories with live service count.
-- service_count includes pending/completed/needs_catalog active rows so vendors
-- see the full count and cannot accidentally delete a referenced category.

DROP FUNCTION IF EXISTS get_my_vendor_categories();

CREATE FUNCTION get_my_vendor_categories()
RETURNS TABLE (
  id            UUID,
  name          TEXT,
  icon_url      TEXT,
  service_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    vc.id,
    vc.name,
    vc.icon_url,
    COUNT(vsr.id) AS service_count
  FROM vendor_categories vc
  LEFT JOIN vendor_service_requests vsr
         ON vsr.vendor_category_id = vc.id
        AND vsr.request_type       = 'new_service'
        AND vsr.status             IN ('pending', 'completed', 'needs_catalog')
        AND vsr.is_active          = true
  WHERE vc.vendor_id IN (
    SELECT id FROM vendors WHERE auth_user_id = auth.uid()
  )
  GROUP BY vc.id, vc.name, vc.icon_url, vc.created_at
  ORDER BY vc.created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION get_my_vendor_categories() TO authenticated;

-- ── 5. Recreate get_vcs_categories() ─────────────────────────────────────────

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
    vc.id,
    vc.name,
    NULL::TEXT  AS slug,
    NULL::TEXT  AS icon_key,
    vc.icon_url AS image_url,
    0::INTEGER  AS sort_order,
    COUNT(DISTINCT vsr.vendor_id) AS vendor_count
  FROM vendor_categories vc
  JOIN vendor_service_requests vsr ON vsr.vendor_category_id = vc.id
  JOIN vendors v                   ON v.id = vsr.vendor_id
  WHERE vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND v.is_active      = true
  GROUP BY vc.id, vc.name, vc.icon_url
  ORDER BY vendor_count DESC, vc.name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_vcs_categories() TO anon, authenticated;

-- ── 6. Recreate get_vcs_vendors() ────────────────────────────────────────────

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
    v.rating::NUMERIC  AS rating,
    v.profile_image_url,
    v.is_online,
    COUNT(DISTINCT vsr.id) AS service_count
  FROM vendors v
  JOIN vendor_service_requests vsr ON vsr.vendor_id = v.id
  WHERE vsr.vendor_category_id = p_category_id
    AND vsr.request_type       = 'new_service'
    AND vsr.status             = 'completed'
    AND vsr.is_active          = true
    AND v.is_active            = true
    AND (
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

-- ── 7. Recreate get_vendor_vcs() ─────────────────────────────────────────────

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
  vendor_category_id UUID,
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
    vsr.vendor_category_id,
    vc.name     AS category_name,
    vc.icon_url AS category_icon_key,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs
  FROM vendor_service_requests vsr
  LEFT JOIN vendor_categories vc ON vc.id = vsr.vendor_category_id
  WHERE vsr.vendor_id    = p_vendor_id
    AND vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND (p_category_id IS NULL OR vsr.vendor_category_id = p_category_id)
  ORDER BY vc.name ASC NULLS LAST, vsr.service_name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_vendor_vcs(UUID, UUID) TO anon, authenticated;

-- ── 8. Recreate search_vendor_custom_services() ──────────────────────────────

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
  vendor_category_id UUID,
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
    v.business_name      AS vendor_name,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs,
    vsr.vendor_category_id,
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
      vsr.service_name   ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY vsr.service_name
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION search_vendor_custom_services(TEXT) TO anon, authenticated;
