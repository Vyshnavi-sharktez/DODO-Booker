-- Allow NULL coordinates in get_preferred_vendors_by_ids_and_location.
-- When p_lat / p_lng are NULL (service detail page, no address yet),
-- return all active configured vendors without location filtering.
-- When coordinates are provided (booking summary), apply the haversine filter.

CREATE OR REPLACE FUNCTION get_preferred_vendors_by_ids_and_location(
  p_vendor_ids TEXT[],
  p_lat        FLOAT8 DEFAULT NULL,
  p_lng        FLOAT8 DEFAULT NULL
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
    LEFT JOIN vendor_serving_area_assignments vsaa ON vsaa.vendor_id    = v.id
    LEFT JOIN vendor_serving_areas            vsa  ON vsa.id            = vsaa.serving_area_id
    WHERE  v.id = ANY(p_vendor_ids::UUID[])
      AND  v.is_active = true
      AND  (
        -- No coordinates supplied: show all configured active vendors
        p_lat IS NULL
        OR p_lng IS NULL
        -- Coordinates supplied: only vendors whose serving area covers the point
        OR (
          vsa.is_active = true
          AND (
            2.0 * 6371.0 * asin(sqrt(
              power(sin(radians((vsa.latitude  - p_lat)  / 2.0)), 2) +
              cos(radians(p_lat)) * cos(radians(vsa.latitude)) *
              power(sin(radians((vsa.longitude - p_lng) / 2.0)), 2)
            ))
          ) <= vsa.radius_km
        )
      )
  ) sub
  ORDER BY sub.rating DESC NULLS LAST, sub.business_name;
$$;
