-- Extends enforce_booking_location() to validate the platform-level service
-- availability zone before inserting a booking.
--
-- Root cause fixed:
--   The previous trigger called check_node_availability() which only checks
--   catalog_node_location_restrictions (per-service exclusion zones). It never
--   called is_location_serviceable(), so a direct DB insert bypassed the
--   platform-level zone check entirely — confirmed with active zones:
--   JNTU College (10 km), KPHB Colony (5 km), Ameerpet (5 km), Uppal (5 km).
--
-- What changes:
--   One new guard is inserted before the existing check_node_availability call.
--   When coordinates are present, is_location_serviceable() is called first.
--   If it returns false the booking is rejected immediately.
--   All other behaviour (NULL-coordinate path, check_node_availability call,
--   existing service-specific restrictions) is unchanged.
--
-- What does NOT change:
--   • The trigger name/definition (function replaced in-place via OR REPLACE).
--   • The NULL-coordinate path: still blocks only when catalog_node_location_restrictions
--     exists for that service, consistent with the original design.
--   • check_node_availability() call and its response handling.
--   • is_location_serviceable() logic/data (not touched).
--   • service_availability_areas data (not touched).
--   • Any existing booking rows (trigger fires on INSERT only).

CREATE OR REPLACE FUNCTION enforce_booking_location()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result       JSONB;
  v_has_restrict BOOLEAN;
BEGIN
  IF NEW.service_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- ── No coordinates: preserve original behaviour ──────────────────────────
  -- Block only when this specific service has catalog_node_location_restrictions.
  -- Platform-level zone check requires coordinates; skip it here.
  IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM   catalog_node_location_restrictions
      WHERE  node_id = NEW.service_id
    ) INTO v_has_restrict;

    IF v_has_restrict THEN
      RAISE EXCEPTION 'Service not available: location restrictions apply but the booking address has no coordinates. Please select an address with a valid location.';
    END IF;

    RETURN NEW;
  END IF;

  -- ── Platform-level serviceability check ──────────────────────────────────
  -- Reuses is_location_serviceable() — no duplication of Haversine logic.
  -- Must pass before per-service restrictions are evaluated.
  -- Returns TRUE when no active zones exist (opt-in feature — zero config = no restriction).
  IF NOT is_location_serviceable(NEW.latitude::NUMERIC, NEW.longitude::NUMERIC) THEN
    RAISE EXCEPTION 'Sorry, we do not currently serve your location.';
  END IF;

  -- ── Per-service / catalog-node availability check (unchanged) ─────────────
  -- Validates catalog_node_location_restrictions, is_active, availability_status.
  -- p_parent_id is NULL at trigger level; relationship-scoped restrictions are
  -- enforced client-side only (same limitation as the original trigger).
  SELECT check_node_availability(
    NEW.service_id,
    NULL,
    NEW.latitude::NUMERIC,
    NEW.longitude::NUMERIC
  ) INTO v_result;

  IF (v_result->>'status') IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION '%', COALESCE(v_result->>'message', 'This service is not available at your location.');
  END IF;

  RETURN NEW;
END;
$$;
