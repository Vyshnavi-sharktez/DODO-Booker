-- Allows get_vcs_vendors to be called with p_category_id = NULL to return all
-- active vendors that have completed custom services across any category.

DROP FUNCTION IF EXISTS get_vcs_vendors(UUID, FLOAT8, FLOAT8);

CREATE FUNCTION get_vcs_vendors(
  p_category_id UUID DEFAULT NULL,
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
  WHERE (p_category_id IS NULL OR vsr.vendor_category_id = p_category_id)
    AND vsr.request_type        = 'new_service'
    AND vsr.status              = 'completed'
    AND vsr.is_active           = true
    AND v.is_active             = true
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

