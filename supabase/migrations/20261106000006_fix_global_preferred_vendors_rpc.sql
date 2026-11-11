-- Fix: preferred vendors with no serving areas configured are treated as
-- serving everywhere (LEFT JOIN instead of INNER JOIN on serving areas).

CREATE OR REPLACE FUNCTION public.get_global_preferred_vendors_by_location(
  p_lat FLOAT8,
  p_lng FLOAT8
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
  SELECT id, business_name, rating, preferred_vendor_fee
  FROM (
    SELECT DISTINCT
      v.id,
      v.business_name,
      v.rating::NUMERIC               AS rating,
      v.preferred_vendor_fee::NUMERIC AS preferred_vendor_fee
    FROM   public.vendors v
    LEFT JOIN public.vendor_serving_area_assignments vsaa ON vsaa.vendor_id = v.id
    LEFT JOIN public.vendor_serving_areas            vsa  ON vsa.id         = vsaa.serving_area_id
                                                        AND vsa.is_active   = TRUE
    WHERE  v.is_preferred_vendor = TRUE
      AND  v.is_active           = TRUE
      AND (
        -- No serving areas configured → serve everywhere
        vsaa.vendor_id IS NULL
        OR (
          -- Serving area exists → check proximity
          (
            2.0 * 6371.0 * asin(sqrt(
              power(sin(radians((vsa.latitude  - p_lat) / 2.0)), 2) +
              cos(radians(p_lat)) * cos(radians(vsa.latitude)) *
              power(sin(radians((vsa.longitude - p_lng) / 2.0)), 2)
            ))
          ) <= vsa.radius_km
        )
      )
  ) sub
  ORDER BY rating DESC NULLS LAST, business_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_global_preferred_vendors_by_location(FLOAT8, FLOAT8)
  TO anon, authenticated;
