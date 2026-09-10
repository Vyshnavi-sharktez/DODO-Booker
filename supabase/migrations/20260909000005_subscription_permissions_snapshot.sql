-- ── Subscription Permissions Snapshot for Global Plans ───────────────────────
--
-- Business rule: admin changes to a subscription_plans row must NOT affect
-- vendors who already hold an active subscription on that plan.  Permissions
-- are snapshotted into vendor_subscriptions.subscription_permissions at
-- purchase time (Dart side already does this for catalog subscriptions;
-- this migration updates the three SQL enforcement functions to honour the
-- snapshot for global subscriptions too).
--
-- Strategy
-- ────────
-- All three functions already read vs.subscription_permissions for catalog
-- subscriptions.  For global subscriptions they currently JOIN subscription_plans
-- and read sp.permissions (live).  The change:
--
--   COALESCE(vs.subscription_permissions->key, sp.permissions->key)
--
-- If the vendor has a snapshot (new purchases), the snapshot wins.
-- If subscription_permissions IS NULL (existing subs created before this
-- migration), sp.permissions is the fallback — identical to current behaviour
-- so no active vendor is disrupted.
--
-- Safe to re-run: CREATE OR REPLACE throughout.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. check_vendor_cod_eligibility ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION check_vendor_cod_eligibility(p_vendor_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_subscription_enabled TEXT;
  v_require_subscription  TEXT;
  v_allow_free_vendors    TEXT;
  v_is_active             BOOLEAN;
  v_allow_cod             BOOLEAN;
BEGIN
  SELECT setting_value INTO v_subscription_enabled
    FROM settings WHERE setting_key = 'subscription_enabled';
  v_subscription_enabled := COALESCE(v_subscription_enabled, 'false');

  SELECT is_active INTO v_is_active FROM vendors WHERE id = p_vendor_id;
  IF NOT FOUND OR NOT v_is_active THEN RETURN FALSE; END IF;

  IF v_subscription_enabled <> 'true' THEN RETURN TRUE; END IF;

  SELECT setting_value INTO v_require_subscription
    FROM settings WHERE setting_key = 'subscription_require_active';
  v_require_subscription := COALESCE(v_require_subscription, 'false');

  SELECT setting_value INTO v_allow_free_vendors
    FROM settings WHERE setting_key = 'subscription_allow_free_vendors';
  v_allow_free_vendors := COALESCE(v_allow_free_vendors, 'true');

  IF v_require_subscription <> 'true' THEN RETURN TRUE; END IF;

  -- Global subscription: prefer snapshot permissions; fall back to live plan.
  SELECT COALESCE(
           (vs.subscription_permissions->>'allow_cod')::BOOLEAN,
           (sp.permissions->>'allow_cod')::BOOLEAN
         )
    INTO v_allow_cod
    FROM vendor_subscriptions vs
    LEFT JOIN subscription_plans sp ON sp.id = vs.plan_id
   WHERE vs.vendor_id       = p_vendor_id
     AND vs.catalog_node_id IS NULL
     AND vs.status          = 'active'
   LIMIT 1;

  IF FOUND THEN
    RETURN COALESCE(v_allow_cod, FALSE);
  END IF;

  -- Catalog subscription: permissions stored inline as snapshot.
  PERFORM 1
    FROM vendor_subscriptions vs
   WHERE vs.vendor_id       = p_vendor_id
     AND vs.catalog_node_id IS NOT NULL
     AND vs.status          = 'active'
     AND (vs.subscription_permissions->>'allow_cod')::BOOLEAN = TRUE
   LIMIT 1;

  IF FOUND THEN RETURN TRUE; END IF;

  RETURN v_allow_free_vendors = 'true';
END;
$$;

-- ── 2. update_vendor_service_custom_price ─────────────────────────────────────

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
  -- 1. Ownership check
  SELECT EXISTS (
    SELECT 1 FROM vendor_services
     WHERE id = p_vendor_service_id AND vendor_id = p_vendor_id
  ) INTO v_owns;

  IF NOT v_owns THEN
    RAISE EXCEPTION 'Vendor does not own this service record'
      USING ERRCODE = 'P0002';
  END IF;

  -- 2. Entitlement check: prefer snapshot permissions; fall back to live plan.
  SELECT EXISTS (
    SELECT 1
      FROM vendor_subscriptions vs
      LEFT JOIN subscription_plans sp ON sp.id = vs.plan_id
     WHERE vs.vendor_id = p_vendor_id
       AND vs.status    = 'active'
       AND COALESCE(
             (vs.subscription_permissions->>'allow_custom_price')::BOOLEAN,
             (sp.permissions->>'allow_custom_price')::BOOLEAN,
             FALSE
           )
  ) INTO v_entitled;

  IF NOT v_entitled THEN
    RAISE EXCEPTION 'Vendor subscription does not include custom pricing'
      USING ERRCODE = 'P0001';
  END IF;

  -- 3. Price validation
  IF p_price IS NOT NULL AND p_price <= 0 THEN
    RAISE EXCEPTION 'Custom price must be greater than zero'
      USING ERRCODE = 'P0001';
  END IF;

  -- 4. Apply
  UPDATE vendor_services
     SET custom_price = p_price
   WHERE id = p_vendor_service_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_vendor_service_custom_price(UUID, UUID, NUMERIC)
  TO anon, authenticated;

-- ── 3. fn_enforce_max_custom_services ────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_enforce_max_custom_services()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_permissions    JSONB;
  v_limit          INTEGER;
  v_existing_count INTEGER;
BEGIN
  -- Only new-service rows consume a slot.
  IF NEW.request_type IS DISTINCT FROM 'new_service' THEN
    RETURN NEW;
  END IF;

  -- Resolve permissions: prefer snapshot; fall back to live plan.
  SELECT COALESCE(vs.subscription_permissions, sp.permissions)
    INTO v_permissions
    FROM vendor_subscriptions vs
    LEFT JOIN subscription_plans sp ON sp.id = vs.plan_id
   WHERE vs.vendor_id       = NEW.vendor_id
     AND vs.catalog_node_id IS NULL
     AND vs.status          = 'active'
     AND vs.expiry_date     > NOW()
   LIMIT 1;

  -- No active subscription → no limit enforced.
  IF v_permissions IS NULL THEN
    RETURN NEW;
  END IF;

  -- false sentinel: feature explicitly disabled — block the insert.
  IF (v_permissions->'max_custom_services') = 'false'::jsonb THEN
    RAISE EXCEPTION
      'Custom service creation is not included in this subscription plan.'
    USING ERRCODE = 'P0001';
  END IF;

  -- Cast to integer now that we know the value is not the boolean false.
  v_limit := (v_permissions->>'max_custom_services')::INTEGER;

  -- Absent key, null, or non-positive → unlimited.
  IF v_limit IS NULL OR v_limit <= 0 THEN
    RETURN NEW;
  END IF;

  -- Count existing applicable custom-service rows.
  SELECT COUNT(*)
    INTO v_existing_count
    FROM vendor_service_requests
   WHERE vendor_id    = NEW.vendor_id
     AND request_type = 'new_service'
     AND status       IN ('completed', 'pending_deletion');

  IF v_existing_count >= v_limit THEN
    RAISE EXCEPTION
      'Custom service limit reached: this subscription plan allows at most % '
      'active custom service(s). Deactivate or remove an existing service '
      'before submitting a new one.',
      v_limit
    USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;
