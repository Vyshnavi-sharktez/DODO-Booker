-- ── Vendor Custom Price ───────────────────────────────────────────────────────
--
-- Adds a SECURITY DEFINER RPC that lets entitled vendors update the
-- custom_price on their own vendor_services rows.
--
-- Entitlement is enforced in the database:
--   • The vendor must own the vendor_services row (vendor_id match).
--   • The vendor must have an active subscription whose permissions include
--     allow_custom_price = true.  Covers both plan-based subscriptions
--     (permissions lives on subscription_plans) and catalog subscriptions
--     (permissions snapshot lives on vendor_subscriptions.subscription_permissions).
--   • price = NULL clears the custom price (reverts to catalog base_price).
--   • price must be > 0 when provided.
--
-- RLS note: vendor_services is queried as anon; the SECURITY DEFINER context
-- runs as the function owner (postgres) so no anon UPDATE policy is needed.
--
-- Safe to re-run: CREATE OR REPLACE throughout.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_vendor_service_custom_price(
  p_vendor_service_id UUID,
  p_vendor_id         UUID,
  p_price             NUMERIC
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owns     BOOLEAN;
  v_entitled BOOLEAN;
BEGIN
  -- ── 1. Ownership check ────────────────────────────────────────────────────
  SELECT EXISTS (
    SELECT 1 FROM vendor_services
     WHERE id = p_vendor_service_id AND vendor_id = p_vendor_id
  ) INTO v_owns;

  IF NOT v_owns THEN
    RAISE EXCEPTION 'Vendor does not own this service record'
      USING ERRCODE = 'P0002';
  END IF;

  -- ── 2. Entitlement check ──────────────────────────────────────────────────
  -- Covers plan-based subs (sp.permissions) and catalog subs
  -- (vs.subscription_permissions snapshot).
  SELECT EXISTS (
    SELECT 1
      FROM vendor_subscriptions vs
      LEFT JOIN subscription_plans sp ON sp.id = vs.plan_id
     WHERE vs.vendor_id = p_vendor_id
       AND vs.status    = 'active'
       AND (
         COALESCE((sp.permissions             ->>'allow_custom_price')::BOOLEAN, FALSE)
         OR
         COALESCE((vs.subscription_permissions->>'allow_custom_price')::BOOLEAN, FALSE)
       )
  ) INTO v_entitled;

  IF NOT v_entitled THEN
    RAISE EXCEPTION 'Vendor subscription does not include custom pricing'
      USING ERRCODE = 'P0001';
  END IF;

  -- ── 3. Price validation (only when setting, not clearing) ─────────────────
  IF p_price IS NOT NULL AND p_price <= 0 THEN
    RAISE EXCEPTION 'Custom price must be greater than zero'
      USING ERRCODE = 'P0001';
  END IF;

  -- ── 4. Apply ──────────────────────────────────────────────────────────────
  UPDATE vendor_services
     SET custom_price = p_price
   WHERE id = p_vendor_service_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_vendor_service_custom_price(UUID, UUID, NUMERIC)
  TO anon, authenticated;
