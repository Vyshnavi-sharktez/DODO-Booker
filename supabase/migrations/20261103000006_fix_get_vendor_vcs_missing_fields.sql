-- ── Fix get_vendor_vcs missing fields ────────────────────────────────────────
--
-- The 20261103000002 version of get_vendor_vcs omitted vendor_id, vendor_name,
-- and the four warranty fields from its SELECT.
--
-- VendorCustomServiceModel.fromMap casts vendor_id and vendor_name as non-
-- nullable String, so any null → TypeError crash when opening a vendor detail.
-- Warranty fields used safe nullable casts so no crash, but warranty info was
-- silently suppressed in the service detail sheet.
--
-- Fix: add all missing fields to the RETURNS TABLE and SELECT.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS get_vendor_vcs(UUID, UUID);

CREATE FUNCTION get_vendor_vcs(
  p_vendor_id   UUID,
  p_category_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id                 UUID,
  service_name       TEXT,
  description        TEXT,
  active_price       NUMERIC,
  image_url          TEXT,
  pricing_type       TEXT,
  price_per_minute   NUMERIC,
  duration_minutes   INTEGER,
  vendor_category_id UUID,
  category_name      TEXT,
  category_icon_key  TEXT,
  rating             NUMERIC,
  review_count       INTEGER,
  included_items     JSONB,
  excluded_items     JSONB,
  before_after_pairs JSONB,
  vendor_id          UUID,
  vendor_name        TEXT,
  warranty_enabled   BOOLEAN,
  warranty_days      INTEGER,
  warranty_covers    TEXT,
  warranty_exclusions TEXT
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
    vc.name     AS category_name,
    vc.icon_url AS category_icon_key,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs,
    vsr.vendor_id,
    v.business_name AS vendor_name,
    vsr.warranty_enabled,
    vsr.warranty_days,
    vsr.warranty_covers,
    vsr.warranty_exclusions
  FROM vendor_service_requests vsr
  LEFT JOIN vendor_categories vc ON vc.id = vsr.vendor_category_id
  JOIN vendors v ON v.id = vsr.vendor_id
  WHERE vsr.vendor_id    = p_vendor_id
    AND vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND (p_category_id IS NULL OR vsr.vendor_category_id = p_category_id)
  ORDER BY vc.name ASC NULLS LAST, vsr.service_name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_vendor_vcs(UUID, UUID) TO anon, authenticated;
