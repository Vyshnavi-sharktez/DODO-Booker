-- Adds city + total_reviews to get_vcs_vendors for vendor header display.
-- Adds options_count to get_vendor_vcs for service card "X options" label.

-- ── 1. get_vcs_vendors: add city and total_reviews ────────────────────────────

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
  service_count     BIGINT,
  city              TEXT,
  total_reviews     BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    v.id,
    v.business_name,
    v.rating::NUMERIC                  AS rating,
    v.profile_image_url,
    v.is_online,
    COUNT(DISTINCT vsr.id)             AS service_count,
    v.city,
    (
      SELECT COALESCE(SUM(r.review_count), 0)
      FROM   vendor_service_requests r
      WHERE  r.vendor_id     = v.id
        AND  r.request_type  = 'new_service'
        AND  r.status        = 'completed'
        AND  r.is_active     = true
    )::BIGINT                          AS total_reviews
  FROM vendors v
  JOIN vendor_service_requests vsr ON vsr.vendor_id = v.id
  WHERE vsr.vendor_category_id = p_category_id
    AND vsr.request_type        = 'new_service'
    AND vsr.status          = 'completed'
    AND vsr.is_active       = true
    AND v.is_active         = true
    AND (
      p_lat IS NULL
      OR p_lng IS NULL
      OR EXISTS (
        SELECT 1
        FROM   vendor_serving_area_assignments vsaa
        JOIN   vendor_serving_areas vsa ON vsa.id = vsaa.serving_area_id
        WHERE  vsaa.vendor_id  = v.id
          AND  vsa.is_active   = true
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

-- ── 2. get_vendor_vcs: add options_count ─────────────────────────────────────

DROP FUNCTION IF EXISTS get_vendor_vcs(UUID, UUID);

CREATE FUNCTION get_vendor_vcs(
  p_vendor_id   UUID,
  p_category_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id                  UUID,
  service_name        TEXT,
  description         TEXT,
  active_price        NUMERIC,
  image_url           TEXT,
  pricing_type        TEXT,
  price_per_minute    NUMERIC,
  duration_minutes    INTEGER,
  vendor_category_id  UUID,
  category_name       TEXT,
  category_icon_key   TEXT,
  rating              NUMERIC,
  review_count        INTEGER,
  included_items      JSONB,
  excluded_items      JSONB,
  before_after_pairs  JSONB,
  vendor_id           UUID,
  vendor_name         TEXT,
  warranty_enabled    BOOLEAN,
  warranty_days       INTEGER,
  warranty_covers     TEXT,
  warranty_exclusions TEXT,
  options_count       INTEGER
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
    vc.name      AS category_name,
    vc.icon_url  AS category_icon_key,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs,
    vsr.vendor_id,
    v.business_name  AS vendor_name,
    vsr.warranty_enabled,
    vsr.warranty_days,
    vsr.warranty_covers,
    vsr.warranty_exclusions,
    (
      SELECT COALESCE(COUNT(sao.id), 0)::INTEGER
      FROM   service_attributes  sa
      JOIN   service_attribute_options sao ON sao.attribute_id = sa.id
      WHERE  sa.custom_service_id = vsr.id
    )            AS options_count
  FROM vendor_service_requests vsr
  LEFT JOIN vendor_categories vc ON vc.id = vsr.vendor_category_id
  JOIN  vendors v ON v.id = vsr.vendor_id
  WHERE vsr.vendor_id    = p_vendor_id
    AND vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND (p_category_id IS NULL OR vsr.vendor_category_id = p_category_id)
  ORDER BY vc.name ASC NULLS LAST, vsr.service_name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_vendor_vcs(UUID, UUID) TO anon, authenticated;
