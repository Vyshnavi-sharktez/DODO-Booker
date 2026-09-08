-- ── Expose content fields in search_vendor_custom_services ───────────────────
--
-- Migration 20260907000004 added included_items, excluded_items,
-- before_after_pairs to vendor_service_requests, but search_vendor_custom_services
-- still returns only the original 9 columns.  Customer-side VendorCustomServiceModel
-- now reads these three fields so the customer detail sheet can show them.
--
-- DROP + CREATE is required because RETURNS TABLE cannot be changed with
-- CREATE OR REPLACE when the column list differs.

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
  WHERE vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND v.is_active      = true
    AND (
      vsr.service_name ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY vsr.service_name
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION search_vendor_custom_services(TEXT) TO anon, authenticated;
