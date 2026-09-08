-- ── Active/Inactive status for vendor custom services ─────────────────────────
--
-- New custom services default to inactive (is_active = false).
-- Both admin and vendor can toggle is_active via the toggle_custom_service_active
-- RPC (SECURITY DEFINER, authorisation enforced inside the function).
-- Customer-facing search_vendor_custom_services now gates on is_active = true
-- in addition to the existing status / vendor.is_active checks.

-- 1. Add is_active column
ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT false;

-- 2. RPC for toggling — callable by authenticated users (admin OR owning vendor)
CREATE OR REPLACE FUNCTION toggle_custom_service_active(
  p_request_id UUID,
  p_is_active   BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req vendor_service_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_req
  FROM vendor_service_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Custom service not found';
  END IF;

  -- Must be a live custom service (new_service + completed or pending_deletion)
  IF v_req.request_type != 'new_service'
     OR v_req.status NOT IN ('completed', 'pending_deletion') THEN
    RAISE EXCEPTION 'Not an active custom service';
  END IF;

  -- Authorisation: admin OR the owning vendor
  IF NOT (
    EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    OR v_req.vendor_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE vendor_service_requests
  SET is_active = p_is_active,
      updated_at = NOW()
  WHERE id = p_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION toggle_custom_service_active(UUID, BOOLEAN) TO authenticated;

-- 3. Update customer search RPC to gate on is_active
--    (DROP + CREATE required because RETURNS TABLE column list changed in 20260907000005)
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
    AND vsr.is_active    = true
    AND v.is_active      = true
    AND (
      vsr.service_name ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY vsr.service_name
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION search_vendor_custom_services(TEXT) TO anon, authenticated;
