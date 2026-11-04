-- ── Vendor Service Pricing V2 ─────────────────────────────────────────────────
--
-- Replaces automatic minutes-based calculation with explicit vendor-controlled
-- pricing:
--
--   fixed          — single price with optional discount (% or fixed amount)
--   duration_based — N (label, price, discount) options stored in
--                    service_attributes / service_attribute_options
--
-- Changes:
--  1. Add discount_type / discount_value columns to vendor_service_requests
--  2. Extend pricing_type CHECK to allow 'duration_based'
--     (minutes_based kept in check for backward compat — no new services use it)
--  3. Update admin_accept_service_request to apply discount when computing
--     active_price on new_service approval
--  4. Update get_vendor_vcs to return price, discount_type, discount_value
--  5. Update search_vendor_custom_services to return same
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Discount columns
ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS discount_type TEXT NOT NULL DEFAULT 'none'
    CHECK (discount_type IN ('none', 'percentage', 'fixed'));

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS discount_value NUMERIC(10,2) NOT NULL DEFAULT 0
    CHECK (discount_value >= 0);

-- 2. Allow 'duration_based' in pricing_type
ALTER TABLE vendor_service_requests
  DROP CONSTRAINT IF EXISTS vendor_service_requests_pricing_type_check;

ALTER TABLE vendor_service_requests
  ADD CONSTRAINT vendor_service_requests_pricing_type_check
    CHECK (pricing_type IN ('fixed', 'minutes_based', 'duration_based'));

-- 3. Update admin_accept_service_request: apply discount to active_price
CREATE OR REPLACE FUNCTION public.admin_accept_service_request(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req          vendor_service_requests%ROWTYPE;
  v_active_price NUMERIC;
BEGIN
  -- Active-admin guard
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE auth_user_id = auth.uid()
      AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Unauthorized: caller is not an active admin'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_req
  FROM vendor_service_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found: %', p_request_id;
  END IF;

  -- ── new_service ─────────────────────────────────────────────────────────────
  IF v_req.request_type = 'new_service' THEN

    IF v_req.status = 'pending_deletion' THEN
      UPDATE vendor_service_requests
        SET status = 'deleted', is_active = FALSE, updated_at = NOW()
        WHERE id = p_request_id;
    ELSE
      -- Compute discounted active_price from the stored discount config
      v_active_price := CASE
        WHEN v_req.discount_type = 'percentage' THEN
          GREATEST(0, v_req.price * (1.0 - v_req.discount_value / 100.0))
        WHEN v_req.discount_type = 'fixed' THEN
          GREATEST(0, v_req.price - v_req.discount_value)
        ELSE
          v_req.price
      END;

      UPDATE vendor_service_requests
        SET status       = 'completed',
            active_price = v_active_price,
            is_active    = EXISTS (
              SELECT 1 FROM public.vendors
              WHERE id = v_req.vendor_id
                AND is_active = TRUE
            ),
            updated_at   = NOW()
        WHERE id = p_request_id;
    END IF;

  -- ── price_change ────────────────────────────────────────────────────────────
  ELSIF v_req.request_type = 'price_change' THEN

    UPDATE vendor_service_requests
      SET price        = COALESCE(v_req.new_price, price),
          active_price = COALESCE(v_req.new_price, active_price),
          service_name = COALESCE(v_req.new_service_name, service_name),
          updated_at   = NOW()
      WHERE id = v_req.parent_request_id;

    UPDATE vendor_service_requests
      SET status = 'completed', updated_at = NOW()
      WHERE id = p_request_id;

  -- ── delete_service (legacy rows) ────────────────────────────────────────────
  ELSIF v_req.request_type = 'delete_service' THEN

    UPDATE vendor_service_requests
      SET status = 'deleted', updated_at = NOW()
      WHERE id = v_req.parent_request_id;

    UPDATE vendor_service_requests
      SET status = 'completed', updated_at = NOW()
      WHERE id = p_request_id;

  -- ── edit_service ────────────────────────────────────────────────────────────
  ELSIF v_req.request_type = 'edit_service' THEN

    UPDATE vendor_service_requests
      SET included_items      = v_req.included_items,
          excluded_items      = v_req.excluded_items,
          before_after_pairs  = v_req.before_after_pairs,
          warranty_enabled    = v_req.warranty_enabled,
          warranty_days       = v_req.warranty_days,
          warranty_covers     = v_req.warranty_covers,
          warranty_exclusions = v_req.warranty_exclusions,
          updated_at          = NOW()
      WHERE id = v_req.parent_request_id;

    DELETE FROM service_attributes
      WHERE custom_service_id = v_req.parent_request_id;

    UPDATE service_attributes
      SET custom_service_id = v_req.parent_request_id
      WHERE custom_service_id = p_request_id;

    UPDATE vendor_service_requests
      SET status = 'completed', updated_at = NOW()
      WHERE id = p_request_id;

  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_accept_service_request(UUID) TO authenticated;

-- 4. Update get_vendor_vcs to return price, discount_type, discount_value
DROP FUNCTION IF EXISTS get_vendor_vcs(UUID, UUID);

CREATE FUNCTION get_vendor_vcs(
  p_vendor_id   UUID,
  p_category_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id                 UUID,
  service_name       TEXT,
  description        TEXT,
  price              NUMERIC,
  active_price       NUMERIC,
  discount_type      TEXT,
  discount_value     NUMERIC,
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
  warranty_exclusions TEXT,
  options_count      INTEGER
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
    vsr.price,
    vsr.active_price,
    vsr.discount_type,
    vsr.discount_value,
    vsr.image_url,
    vsr.pricing_type,
    vsr.price_per_minute,
    vsr.duration_minutes,
    vsr.vendor_category_id,
    vc.name      AS category_name,
    vc.icon_url  AS category_icon_key,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs,
    vsr.vendor_id,
    v.business_name  AS vendor_name,
    vsr.warranty_enabled,
    vsr.warranty_days,
    vsr.warranty_covers,
    vsr.warranty_exclusions,
    (
      SELECT COALESCE(COUNT(sao.id), 0)::INTEGER
      FROM   service_attributes  sa
      JOIN   service_attribute_options sao ON sao.attribute_id = sa.id
      WHERE  sa.custom_service_id = vsr.id
    )            AS options_count
  FROM vendor_service_requests vsr
  LEFT JOIN vendor_categories vc ON vc.id = vsr.vendor_category_id
  JOIN  vendors v ON v.id = vsr.vendor_id
  WHERE vsr.vendor_id    = p_vendor_id
    AND vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND (p_category_id IS NULL OR vsr.vendor_category_id = p_category_id)
  ORDER BY vc.name ASC NULLS LAST, vsr.service_name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_vendor_vcs(UUID, UUID) TO anon, authenticated;

-- 5. Update search_vendor_custom_services to return price, discount_type, discount_value
DROP FUNCTION IF EXISTS search_vendor_custom_services(TEXT);

CREATE FUNCTION search_vendor_custom_services(p_query TEXT)
RETURNS TABLE (
  id                 UUID,
  service_name       TEXT,
  description        TEXT,
  price              NUMERIC,
  active_price       NUMERIC,
  discount_type      TEXT,
  discount_value     NUMERIC,
  image_url          TEXT,
  vendor_id          UUID,
  vendor_name        TEXT,
  rating             NUMERIC,
  review_count       INTEGER,
  included_items     JSONB,
  excluded_items     JSONB,
  before_after_pairs JSONB,
  vendor_category_id UUID,
  pricing_type       TEXT,
  price_per_minute   NUMERIC,
  duration_minutes   INTEGER
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
    vsr.price,
    vsr.active_price,
    vsr.discount_type,
    vsr.discount_value,
    vsr.image_url,
    vsr.vendor_id,
    v.business_name      AS vendor_name,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs,
    vsr.vendor_category_id,
    vsr.pricing_type,
    vsr.price_per_minute,
    vsr.duration_minutes
  FROM vendor_service_requests vsr
  JOIN vendors v ON v.id = vsr.vendor_id
  WHERE vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND v.is_active      = true
    AND (
      vsr.service_name   ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY vsr.service_name
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION search_vendor_custom_services(TEXT) TO anon, authenticated;
