-- ============================================================
-- Coupon Customer Eligibility
-- ============================================================
-- Adds per-customer restriction support to coupons:
--   - customer_eligibility column on coupons ('all' | 'selected')
--   - coupon_customer_restrictions junction table
--   - Updated validate_coupon RPC (backward compatible: new param has DEFAULT NULL)
-- ============================================================

-- ── 1. customer_eligibility column ───────────────────────────────────────────

ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS customer_eligibility TEXT NOT NULL DEFAULT 'all'
    CHECK (customer_eligibility IN ('all', 'selected'));

-- ── 2. coupon_customer_restrictions junction table ────────────────────────────

CREATE TABLE IF NOT EXISTS public.coupon_customer_restrictions (
  coupon_id   UUID NOT NULL REFERENCES public.coupons(id)     ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES public.customers(id)   ON DELETE CASCADE,
  PRIMARY KEY (coupon_id, customer_id)
);

CREATE INDEX IF NOT EXISTS idx_ccr_coupon_id   ON public.coupon_customer_restrictions(coupon_id);
CREATE INDEX IF NOT EXISTS idx_ccr_customer_id ON public.coupon_customer_restrictions(customer_id);

-- RLS
ALTER TABLE public.coupon_customer_restrictions ENABLE ROW LEVEL SECURITY;

-- Admins: full access
CREATE POLICY "Admins manage coupon_customer_restrictions"
  ON public.coupon_customer_restrictions
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE auth_user_id = auth.uid() AND is_active = true
    )
  );

-- Customers: read own restrictions (needed for coupon lookup on customer app)
CREATE POLICY "Customers read own restrictions"
  ON public.coupon_customer_restrictions
  FOR SELECT
  TO authenticated
  USING (
    customer_id = (
      SELECT id FROM public.customers
      WHERE auth_user_id = auth.uid()
      LIMIT 1
    )
  );

-- ── 3. Updated validate_coupon RPC ────────────────────────────────────────────
-- Adds optional p_customer_id parameter (DEFAULT NULL → backward compatible).
-- Old callers with 3 arguments continue to work unchanged.
-- Customer eligibility check is inserted after usage-limit, before applicability.

DROP FUNCTION IF EXISTS validate_coupon(TEXT, NUMERIC, UUID[]);

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

  -- ── Customer eligibility ───────────────────────────────────────────────────
  -- Only enforced when coupon is 'selected' and a customer ID is supplied.
  -- If no customer ID is passed (guest / no auth), treat as ineligible for
  -- 'selected' coupons so anonymous callers can't bypass the restriction.
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
-- Old 3-arg signature is gone; grant the new 4-arg signature (p_customer_id has DEFAULT NULL,
-- so callers that only pass 3 args still work via named/positional defaults).
-- anon grant: customer app uses custom dev_auth (anon Supabase role), not Supabase Auth.
