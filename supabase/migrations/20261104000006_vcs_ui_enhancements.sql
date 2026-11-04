-- ── VCS UI enhancements ───────────────────────────────────────────────────────
-- 1. Add min_service_price to get_vcs_vendors for price-sort filter
-- 2. Add get_vcs_vendor_service_names RPC for service-category filter chips

-- ── 1. Recreate get_vcs_vendors with min_service_price ───────────────────────

DROP FUNCTION IF EXISTS get_vcs_vendors(UUID, FLOAT8, FLOAT8);

CREATE FUNCTION get_vcs_vendors(
  p_category_id UUID   DEFAULT NULL,
  p_lat         FLOAT8 DEFAULT NULL,
  p_lng         FLOAT8 DEFAULT NULL
)
RETURNS TABLE (
  id                UUID,
  business_name     TEXT,
  rating            NUMERIC,
  profile_image_url TEXT,
  is_online         BOOLEAN,
  service_count     BIGINT,
  city              TEXT,
  total_reviews     BIGINT,
  min_service_price NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    v.id,
    v.business_name,
    v.rating::NUMERIC                 AS rating,
    v.profile_image_url,
    v.is_online,
    COUNT(DISTINCT vsr.id)            AS service_count,
    v.city,
    (
      SELECT COALESCE(SUM(r.review_count), 0)
      FROM   vendor_service_requests r
      WHERE  r.vendor_id    = v.id
        AND  r.request_type = 'new_service'
        AND  r.status       = 'completed'
        AND  r.is_active    = true
    )::BIGINT                         AS total_reviews,
    MIN(vsr.active_price)             AS min_service_price
  FROM vendors v
  JOIN vendor_service_requests vsr ON vsr.vendor_id = v.id
  WHERE (p_category_id IS NULL OR vsr.vendor_category_id = p_category_id)
    AND vsr.request_type   = 'new_service'
    AND vsr.status         = 'completed'
    AND vsr.is_active      = true
    AND v.is_active        = true
    AND (
      p_lat IS NULL
      OR p_lng IS NULL
      OR EXISTS (
        SELECT 1
        FROM   vendor_serving_area_assignments vsaa
        JOIN   vendor_serving_areas vsa ON vsa.id = vsaa.serving_area_id
        WHERE  vsaa.vendor_id = v.id
          AND  vsa.is_active  = true
          AND  (
            2.0 * 6371.0 * asin(sqrt(
              power(sin(radians((vsa.latitude  - p_lat) / 2.0)), 2) +
              cos(radians(p_lat)) * cos(radians(vsa.latitude)) *
              power(sin(radians((vsa.longitude - p_lng) / 2.0)), 2)
            ))
          ) <= vsa.radius_km
      )
    )
  GROUP BY v.id, v.business_name, v.rating, v.profile_image_url, v.is_online, v.city
  ORDER BY v.rating DESC NULLS LAST, v.business_name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_vcs_vendors(UUID, FLOAT8, FLOAT8) TO anon, authenticated;

-- ── 2. get_vcs_vendor_service_names ──────────────────────────────────────────
-- Returns distinct (vendor_id, service_name) pairs for a category.
-- Used client-side to build the Service Category filter: index vendor IDs
-- by service name so the UI can filter the vendor list in one pass.

CREATE OR REPLACE FUNCTION get_vcs_vendor_service_names(p_category_id UUID)
RETURNS TABLE (
  vendor_id    UUID,
  service_name TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT
    vsr.vendor_id,
    vsr.service_name
  FROM vendor_service_requests vsr
  JOIN vendors v ON v.id = vsr.vendor_id
  WHERE vsr.vendor_category_id = p_category_id
    AND vsr.request_type       = 'new_service'
    AND vsr.status             = 'completed'
    AND vsr.is_active          = true
    AND v.is_active            = true
  ORDER BY vsr.service_name;
$$;

GRANT EXECUTE ON FUNCTION get_vcs_vendor_service_names(UUID) TO anon, authenticated;
