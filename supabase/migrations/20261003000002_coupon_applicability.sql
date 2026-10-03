-- ============================================================
-- Coupon Applicability: category / service targeting
-- ============================================================
-- Adds applicability_type and applicable_node_ids to coupons
-- and a server-side validate_coupon RPC that is the final
-- authority for coupon eligibility (cart-aware).
-- ============================================================

-- ── 1. Schema changes ─────────────────────────────────────────────────────────

ALTER TABLE coupons
  ADD COLUMN IF NOT EXISTS applicability_type TEXT NOT NULL DEFAULT 'all'
    CHECK (applicability_type IN ('all', 'categories', 'services')),
  ADD COLUMN IF NOT EXISTS applicable_node_ids UUID[] NOT NULL DEFAULT '{}';

-- Index for fast lookups when resolving names
CREATE INDEX IF NOT EXISTS idx_coupons_applicable_node_ids
  ON coupons USING GIN (applicable_node_ids);


-- ── 2. validate_coupon RPC ────────────────────────────────────────────────────
-- Performs ALL eligibility checks server-side and returns JSONB:
--   { valid: true,  coupon_id: UUID, discount: NUMERIC }
--   { valid: false, error: TEXT }
--
-- p_cart_node_ids: array of catalog_node ids from the customer's cart
--   (include serviceId, parentNodeId, rootCategoryId for each item)

CREATE OR REPLACE FUNCTION validate_coupon(
  p_code           TEXT,
  p_subtotal       NUMERIC,
  p_cart_node_ids  UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coupon            coupons%ROWTYPE;
  v_applicable        BOOLEAN;
  v_applicable_names  TEXT[];
  v_discount          NUMERIC;
BEGIN
  -- ── Find the coupon ────────────────────────────────────────────────────────
  SELECT * INTO v_coupon
  FROM coupons
  WHERE UPPER(code) = UPPER(p_code)
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Coupon not found or inactive.');
  END IF;

  -- ── Date validity ──────────────────────────────────────────────────────────
  IF v_coupon.valid_from IS NOT NULL AND CURRENT_DATE < v_coupon.valid_from THEN
    RETURN jsonb_build_object('valid', false, 'error', 'This coupon is not active yet.');
  END IF;

  IF v_coupon.valid_to IS NOT NULL AND CURRENT_DATE > v_coupon.valid_to THEN
    RETURN jsonb_build_object('valid', false, 'error', 'This coupon has expired.');
  END IF;

  -- ── Usage limit ────────────────────────────────────────────────────────────
  IF v_coupon.usage_limit IS NOT NULL AND v_coupon.used_count >= v_coupon.usage_limit THEN
    RETURN jsonb_build_object('valid', false, 'error', 'This coupon has reached its usage limit.');
  END IF;

  -- ── Minimum order ──────────────────────────────────────────────────────────
  IF v_coupon.min_order_amount IS NOT NULL AND p_subtotal < v_coupon.min_order_amount THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error', format('Minimum order amount is ₹%s.', v_coupon.min_order_amount::INTEGER)
    );
  END IF;

  -- ── Applicability check ───────────────────────────────────────────────────
  IF v_coupon.applicability_type = 'all' OR array_length(v_coupon.applicable_node_ids, 1) IS NULL THEN
    v_applicable := TRUE;

  ELSIF v_coupon.applicability_type = 'services' THEN
    -- Direct: at least one cart node must be in applicable_node_ids
    SELECT EXISTS (
      SELECT 1 FROM unnest(p_cart_node_ids) AS t(id)
      WHERE t.id = ANY(v_coupon.applicable_node_ids)
    ) INTO v_applicable;

  ELSIF v_coupon.applicability_type = 'categories' THEN
    -- Ancestor walk: at least one cart node must be a descendant of an
    -- applicable category, checked recursively via catalog_node_relationships.
    SELECT EXISTS (
      WITH RECURSIVE ancestors AS (
        SELECT t.id AS node_id FROM unnest(p_cart_node_ids) AS t(id)
        UNION
        SELECT cnr.parent_id
        FROM catalog_node_relationships cnr
        INNER JOIN ancestors a ON cnr.child_id = a.node_id
      )
      SELECT 1 FROM ancestors
      WHERE node_id = ANY(v_coupon.applicable_node_ids)
    ) INTO v_applicable;

  ELSE
    v_applicable := FALSE;
  END IF;

  IF NOT v_applicable THEN
    SELECT ARRAY_AGG(name ORDER BY name) INTO v_applicable_names
    FROM catalog_nodes
    WHERE id = ANY(v_coupon.applicable_node_ids);

    RETURN jsonb_build_object(
      'valid', false,
      'error', CASE
        WHEN v_applicable_names IS NOT NULL AND array_length(v_applicable_names, 1) > 0
        THEN format('This coupon is valid only on: %s.', array_to_string(v_applicable_names, ', '))
        ELSE 'This coupon is not valid for items in your cart.'
      END
    );
  END IF;

  -- ── Discount calculation ───────────────────────────────────────────────────
  IF v_coupon.discount_type = 'percentage' THEN
    v_discount := p_subtotal * (v_coupon.discount_value / 100.0);
    IF v_coupon.max_discount_amount IS NOT NULL THEN
      v_discount := LEAST(v_discount, v_coupon.max_discount_amount);
    END IF;
  ELSE
    v_discount := v_coupon.discount_value;
  END IF;
  v_discount := LEAST(v_discount, p_subtotal);

  RETURN jsonb_build_object(
    'valid',     true,
    'coupon_id', v_coupon.id,
    'discount',  v_discount
  );
END;
$$;

GRANT EXECUTE ON FUNCTION validate_coupon(TEXT, NUMERIC, UUID[]) TO authenticated;
