-- ── priority_listing: surface subscribers first in customer custom-service search ──
--
-- search_vendor_custom_services previously ordered results alphabetically by
-- service_name. Vendors with an active global subscription plan where
-- priority_listing = true now appear first, still sorted alphabetically within
-- each group. No change to the function's return columns or callers.

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
  before_after_pairs JSONB
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH priority_vendors AS (
    SELECT DISTINCT vs.vendor_id
    FROM vendor_subscriptions vs
    JOIN subscription_plans sp ON sp.id = vs.plan_id
    WHERE vs.catalog_node_id IS NULL
      AND vs.status         = 'active'
      AND vs.expiry_date    > NOW()
      AND (sp.permissions->>'priority_listing')::boolean = true
  )
  SELECT
    vsr.id,
    vsr.service_name,
    vsr.description,
    vsr.active_price,
    vsr.image_url,
    vsr.vendor_id,
    v.business_name     AS vendor_name,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs
  FROM vendor_service_requests vsr
  JOIN vendors v ON v.id = vsr.vendor_id
  LEFT JOIN priority_vendors pv ON pv.vendor_id = vsr.vendor_id
  WHERE vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND v.is_active      = true
    AND (
      vsr.service_name ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY (pv.vendor_id IS NOT NULL) DESC, vsr.service_name
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION search_vendor_custom_services(TEXT) TO anon, authenticated;
