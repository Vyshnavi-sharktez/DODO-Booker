-- ── max_custom_services: handle explicit false sentinel ──────────────────────
--
-- Context
-- ───────
-- The admin plan form now writes max_custom_services = false (JSON boolean)
-- when the toggle is OFF, meaning "feature disabled — no custom services
-- allowed."  The previous trigger only handled integer limits and NULL; it
-- treated NULL (key absent) as "unlimited."  The new sentinel must be caught
-- before the ::INTEGER cast, which would throw on the string 'false'.
--
-- Three states in permissions JSON after this migration
-- ──────────────────────────────────────────────────────
--   Key absent / null  →  feature on, no cap (unlimited)
--   false (boolean)    →  feature disabled (RAISE P0001)
--   N (integer > 0)    →  feature on, cap of N
--
-- Backward compatibility
-- ──────────────────────
-- Plans created before this migration have the key absent (treated as
-- unlimited).  Plans that already stored an integer limit are unaffected.
-- Only plans where the admin explicitly toggles OFF will store false.
-- ─────────────────────────────────────────────────────────────────────────────

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

  -- Resolve the vendor's active global subscription plan.
  SELECT sp.permissions
    INTO v_permissions
    FROM vendor_subscriptions vs
    JOIN subscription_plans   sp ON sp.id = vs.plan_id
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

-- Trigger registration is unchanged; recreating the function is sufficient
-- because the trigger already points to fn_enforce_max_custom_services.
