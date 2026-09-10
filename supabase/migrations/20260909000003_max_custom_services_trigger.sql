-- ── max_custom_services: server-side insert guard for custom-service requests ──
--
-- Context
-- ───────
-- vendor_service_requests holds new-service proposals from vendors.  The
-- subscription plan's permissions JSONB may contain max_custom_services (a
-- positive integer), capping how many active custom services a vendor may have
-- at once.  Without this trigger the limit is only enforced by Flutter UI code,
-- which is bypassable via direct Supabase REST calls, the dashboard, or
-- concurrent submissions from multiple devices.
--
-- What this migration adds
-- ────────────────────────
-- fn_enforce_max_custom_services() — BEFORE INSERT trigger function.
-- trg_enforce_max_custom_services — Trigger on vendor_service_requests.
--
-- Enforcement semantics
-- ─────────────────────
-- Only rows with request_type = 'new_service' are checked.
-- Price-change and delete_service rows do not create additional services and
-- are exempt.
--
-- "Applicable" count mirrors VendorServiceRequestModel.isActiveCustomService
-- in the Dart vendor app (vendor_service_request_model.dart:44):
--   request_type = 'new_service'
--   AND status IN ('completed', 'pending_deletion')
--
-- A row in 'pending' or 'needs_catalog' is not a live service yet and does not
-- count.  A row in 'pending_deletion' still counts — the vendor still holds
-- that slot until admin approves deletion.
--
-- Decision table
-- ──────────────
-- Condition                                                   │ Result
-- ─────────────────────────────────────────────────────────── │ ────────────
-- request_type ≠ 'new_service'                                │ PASS (exempt)
-- No active global subscription, or permission absent / null  │ PASS (no limit)
-- existing_count < limit                                      │ PASS
-- existing_count >= limit                                     │ RAISE P0001
--
-- Reduced limits never delete existing services — they only block future
-- inserts until the vendor's count falls below the new cap.
--
-- Concurrent submission protection
-- ─────────────────────────────────
-- The trigger fires within the inserting transaction.  Two simultaneous
-- 'pending' inserts both count existing applicable rows at their read time;
-- pending rows do not increment the count, so two concurrent submissions at
-- the limit boundary may both pass (both land as 'pending').  The admin
-- approval path (status UPDATE) is not a new INSERT, so the trigger does not
-- fire there.  This matches the Dart-side check — a higher degree of
-- serialisation would require application-level advisory locks or SERIALIZABLE
-- isolation, which is outside the scope of this feature.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_enforce_max_custom_services()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit          INTEGER;
  v_existing_count INTEGER;
BEGIN
  -- Only new-service rows consume a slot; price-change / delete_service do not.
  IF NEW.request_type IS DISTINCT FROM 'new_service' THEN
    RETURN NEW;
  END IF;

  -- Resolve the vendor's active global subscription plan.
  -- catalog_node_id IS NULL selects the global plan (not a catalog-scoped one).
  -- LIMIT 1: the unique index on vendor_subscriptions(vendor_id) WHERE
  --   status IN ('active','pending') guarantees at most one active row, but
  --   LIMIT 1 makes the intent explicit and avoids any future surprise.
  SELECT (sp.permissions->>'max_custom_services')::INTEGER
    INTO v_limit
    FROM vendor_subscriptions vs
    JOIN subscription_plans   sp ON sp.id = vs.plan_id
   WHERE vs.vendor_id       = NEW.vendor_id
     AND vs.catalog_node_id IS NULL
     AND vs.status          = 'active'
     AND vs.expiry_date     > NOW()
   LIMIT 1;

  -- No active subscription, or permission key absent / null → unlimited.
  IF v_limit IS NULL OR v_limit <= 0 THEN
    RETURN NEW;
  END IF;

  -- Count the vendor's existing applicable custom-service rows.
  -- 'completed'       — live, visible to customers.
  -- 'pending_deletion' — live but vendor-requested for removal; slot still held.
  -- This query runs BEFORE the new row is written, so it reflects the
  -- pre-insert state: no risk of counting the incoming row.
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

DROP TRIGGER IF EXISTS trg_enforce_max_custom_services ON vendor_service_requests;
CREATE TRIGGER trg_enforce_max_custom_services
  BEFORE INSERT ON vendor_service_requests
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_max_custom_services();
