-- Fix: get_instahelp_vendors_by_location was joining vendor_serving_areas
-- but vendor_serving_area_assignments.serving_area_id references
-- service_availability_areas. Vendors with assignments were always excluded.

CREATE OR REPLACE FUNCTION public.get_instahelp_vendors_by_location(
  p_lat FLOAT8,
  p_lng FLOAT8
)
RETURNS TABLE (
  id                UUID,
  business_name     TEXT,
  profile_image_url TEXT,
  is_online         BOOLEAN,
  rating            NUMERIC,
  service_count     BIGINT,
  min_service_price NUMERIC,
  city              TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    v.id,
    v.business_name,
    v.profile_image_url,
    v.is_online,
    v.rating::NUMERIC,
    COUNT(DISTINCT vsr.id)      AS service_count,
    MIN(vsr.price)::NUMERIC     AS min_service_price,
    v.city
  FROM public.vendors v
  LEFT JOIN public.vendor_serving_area_assignments vsaa
         ON vsaa.vendor_id = v.id
  LEFT JOIN public.service_availability_areas saa   -- was: vendor_serving_areas
         ON saa.id = vsaa.serving_area_id
        AND saa.is_active = TRUE
  LEFT JOIN public.vendor_service_requests vsr
         ON vsr.vendor_id = v.id
        AND vsr.status = 'approved'
        AND vsr.is_active = TRUE
  WHERE v.is_active = TRUE
    AND (
      -- Vendor has no area assignments → serves everywhere
      vsaa.vendor_id IS NULL
      OR (
        -- Vendor has assignments → check haversine distance
        (2.0 * 6371.0 * asin(sqrt(
          power(sin(radians((saa.latitude  - p_lat) / 2.0)), 2) +
          cos(radians(p_lat)) * cos(radians(saa.latitude)) *
          power(sin(radians((saa.longitude - p_lng) / 2.0)), 2)
        ))) <= saa.radius_km
      )
    )
  GROUP BY v.id, v.business_name, v.profile_image_url, v.is_online, v.rating, v.city
  ORDER BY v.is_online DESC NULLS LAST, v.rating DESC NULLS LAST, v.business_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_instahelp_vendors_by_location(FLOAT8, FLOAT8)
  TO anon, authenticated;
