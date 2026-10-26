-- ============================================================
-- Fix: max_order_wise_limit is a minimum-order eligibility
--      threshold, not a per-customer redemption cap.
-- ============================================================
-- Previous implementation (20261022000003) counted how many
-- times a customer had used THIS SPECIFIC coupon and blocked
-- once count >= limit (cap).
--
-- Correct behaviour: count the customer's TOTAL qualifying
-- orders (status NOT IN ('cancelled','rejected')).  Reject the
-- coupon if that total is LESS THAN the configured threshold.
--
-- Qualifying order definition reused from existing usage:
--   bookings WHERE status NOT IN ('cancelled', 'rejected')
-- ============================================================

-- ── 1. Helper RPC: customer total qualifying order count ──────────────────────
-- SECURITY DEFINER so the customer app (custom phone-auth, no Supabase session)
-- can query this without hitting RLS on the bookings table.

CREATE OR REPLACE FUNCTION get_customer_order_count(
  p_customer_id UUID
)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::INTEGER
  FROM bookings
  WHERE customer_id = p_customer_id
    AND status NOT IN ('cancelled', 'rejected');
$$;

GRANT EXECUTE ON FUNCTION get_customer_order_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_customer_order_count(UUID) TO anon;

-- ── 2. Updated validate_coupon RPC ────────────────────────────────────────────
-- Replaces the erroneous coupon-use-count block with a total-order-count block.

DROP FUNCTION IF EXISTS validate_coupon(TEXT, NUMERIC, UUID[], UUID);

CREATE OR REPLACE FUNCTION validate_coupon(
  p_code          TEXT,
  p_subtotal      NUMERIC,
  p_cart_node_ids UUID[],
  p_customer_id   UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coupon              coupons%ROWTYPE;
  v_applicable          BOOLEAN;
  v_applicable_names    TEXT[];
  v_discount            NUMERIC;
  v_customer_order_count INTEGER;
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

  -- ── Global usage limit ─────────────────────────────────────────────────────
  IF v_coupon.usage_limit IS NOT NULL AND v_coupon.used_count >= v_coupon.usage_limit THEN
    RETURN jsonb_build_object('valid', false, 'error', 'This coupon has reached its usage limit.');
  END IF;

  -- ── Customer eligibility ───────────────────────────────────────────────────
  IF v_coupon.customer_eligibility = 'selected' THEN
    IF p_customer_id IS NULL THEN
      RETURN jsonb_build_object('valid', false, 'error', 'This coupon is restricted to selected customers.');
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM coupon_customer_restrictions
      WHERE coupon_id   = v_coupon.id
        AND customer_id = p_customer_id
    ) THEN
      RETURN jsonb_build_object('valid', false, 'error', 'This coupon is not available for your account.');
    END IF;
  END IF;

  -- ── Max Order Wise: minimum total-order threshold ──────────────────────────
  -- Only enforced when eligibility is 'all' and a threshold is configured.
  -- Counts the customer's TOTAL non-cancelled/rejected bookings (regardless
  -- of which coupon, if any, was applied to them).
  -- Customers below the threshold, or unauthenticated callers, are rejected.
  IF v_coupon.customer_eligibility = 'all'
     AND v_coupon.max_order_wise_limit IS NOT NULL THEN

    IF p_customer_id IS NULL THEN
      RETURN jsonb_build_object('valid', false, 'error', 'Please sign in to use this coupon.');
    END IF;

    SELECT COUNT(*)::INTEGER INTO v_customer_order_count
    FROM bookings
    WHERE customer_id = p_customer_id
      AND status NOT IN ('cancelled', 'rejected');

    IF v_customer_order_count < v_coupon.max_order_wise_limit THEN
      RETURN jsonb_build_object(
        'valid', false,
        'error', format(
          'This coupon requires a minimum of %s completed orders. You currently have %s.',
          v_coupon.max_order_wise_limit,
          v_customer_order_count
        )
      );
    END IF;
  END IF;

  -- ── Minimum order amount ───────────────────────────────────────────────────
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
    SELECT EXISTS (
      SELECT 1 FROM unnest(p_cart_node_ids) AS t(id)
      WHERE t.id = ANY(v_coupon.applicable_node_ids)
    ) INTO v_applicable;

  ELSIF v_coupon.applicability_type = 'categories' THEN
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

GRANT EXECUTE ON FUNCTION validate_coupon(TEXT, NUMERIC, UUID[], UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION validate_coupon(TEXT, NUMERIC, UUID[], UUID) TO anon;
