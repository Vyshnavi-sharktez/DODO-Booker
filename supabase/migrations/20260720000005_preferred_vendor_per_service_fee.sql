-- Per-service preferred vendor fee override.
--
-- Changes get_preferred_vendors_by_ids_and_location to accept an optional
-- p_vendor_fees JSONB map ({"vendor-uuid": fee_number}).  When a vendor's
-- ID appears as a key, that value is returned as preferred_vendor_fee instead
-- of vendors.preferred_vendor_fee.  Old callers that omit the parameter
-- (or pass NULL) continue to receive the global per-vendor fee unchanged.

CREATE OR REPLACE FUNCTION get_preferred_vendors_by_ids_and_location(
  p_vendor_ids  TEXT[],
  p_lat         FLOAT8 DEFAULT NULL,
  p_lng         FLOAT8 DEFAULT NULL,
  p_vendor_fees JSONB  DEFAULT NULL
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
      v.rating::NUMERIC AS rating,
      COALESCE(
        (p_vendor_fees->>(v.id::TEXT))::NUMERIC,
        v.preferred_vendor_fee::NUMERIC
      ) AS preferred_vendor_fee
    FROM   vendors                         v
    LEFT JOIN vendor_serving_area_assignments vsaa ON vsaa.vendor_id    = v.id
    LEFT JOIN vendor_serving_areas            vsa  ON vsa.id            = vsaa.serving_area_id
    WHERE  v.id = ANY(p_vendor_ids::UUID[])
      AND  v.is_active = true
      AND  (
        p_lat IS NULL
        OR p_lng IS NULL
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
