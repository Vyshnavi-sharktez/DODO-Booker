-- Add p_mode_type parameter so the RPC only returns vendors who have that
-- specific mode active. If the vendor's Scheduled toggle is OFF, they won't
-- appear when customers search for Scheduled vendors.

CREATE OR REPLACE FUNCTION public.get_instahelp_vendors_by_location(
  p_lat       FLOAT8,
  p_lng       FLOAT8,
  p_mode_type TEXT DEFAULT NULL   -- 'scheduled' | 'instant' | 'car_wash' | NULL = all
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
  LEFT JOIN public.service_availability_areas saa
         ON saa.id = vsaa.serving_area_id
        AND saa.is_active = TRUE
  LEFT JOIN public.vendor_service_requests vsr
         ON vsr.vendor_id = v.id
        AND vsr.status = 'approved'
        AND vsr.is_active = TRUE
  WHERE v.is_active = TRUE
    -- Location filter: no assignment = serves everywhere; else haversine check
    AND (
      vsaa.vendor_id IS NULL
      OR (
        (2.0 * 6371.0 * asin(sqrt(
          power(sin(radians((saa.latitude  - p_lat) / 2.0)), 2) +
          cos(radians(p_lat)) * cos(radians(saa.latitude)) *
          power(sin(radians((saa.longitude - p_lng) / 2.0)), 2)
        ))) <= saa.radius_km
      )
    )
    -- Mode filter: only return vendors who have that mode active
    AND (
      p_mode_type IS NULL
      OR EXISTS (
        SELECT 1 FROM public.instahelp_modes im
        WHERE im.vendor_id = v.id
          AND im.mode_type = p_mode_type
          AND im.is_active = TRUE
      )
    )
  GROUP BY v.id, v.business_name, v.profile_image_url, v.is_online, v.rating, v.city
  ORDER BY v.is_online DESC NULLS LAST, v.rating DESC NULLS LAST, v.business_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_instahelp_vendors_by_location(FLOAT8, FLOAT8, TEXT)
  TO anon, authenticated;
