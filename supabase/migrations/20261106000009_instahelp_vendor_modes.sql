-- 1. Add vendor_id to instahelp_modes so vendors can own their own modes.
--    NULL = admin-global (existing behaviour). Set = vendor-owned mode.
ALTER TABLE public.instahelp_modes
  ADD COLUMN IF NOT EXISTS vendor_id UUID REFERENCES public.vendors(id) ON DELETE CASCADE;

-- 2. Update fetchModeIds RPC-less filter: existing global queries can filter
--    WHERE vendor_id IS NULL; vendor-specific queries filter WHERE vendor_id = ?.
--    No DB function needed — handled via PostgREST filters in the app.

-- 3. RPC: get active vendors that serve a coordinate, for the InstaHelp
--    vendor-discovery screen. Returns all active vendors in the area ordered
--    by online status then rating.
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
    COUNT(DISTINCT vsr.id)                             AS service_count,
    MIN(vsr.price)::NUMERIC                            AS min_service_price,
    v.city
  FROM public.vendors v
  LEFT JOIN public.vendor_serving_area_assignments vsaa
         ON vsaa.vendor_id = v.id
  LEFT JOIN public.vendor_serving_areas vsa
         ON vsa.id = vsaa.serving_area_id
        AND vsa.is_active = TRUE
  LEFT JOIN public.vendor_service_requests vsr
         ON vsr.vendor_id = v.id
        AND vsr.status = 'approved'
        AND vsr.is_active = TRUE
  WHERE v.is_active = TRUE
    AND (
      -- No serving areas configured → serves everywhere
      vsaa.vendor_id IS NULL
      OR (
        (2.0 * 6371.0 * asin(sqrt(
          power(sin(radians((vsa.latitude  - p_lat) / 2.0)), 2) +
          cos(radians(p_lat)) * cos(radians(vsa.latitude)) *
          power(sin(radians((vsa.longitude - p_lng) / 2.0)), 2)
        ))) <= vsa.radius_km
      )
    )
  GROUP BY v.id, v.business_name, v.profile_image_url, v.is_online, v.rating, v.city
  ORDER BY v.is_online DESC NULLS LAST, v.rating DESC NULLS LAST, v.business_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_instahelp_vendors_by_location(FLOAT8, FLOAT8)
  TO anon, authenticated;
