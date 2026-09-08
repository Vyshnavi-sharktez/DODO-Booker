-- ── Guard: prevent booking inactive custom services ──────────────────────────
--
-- A BEFORE INSERT trigger on booking_items raises an exception when
-- custom_service_id points to a vendor_service_requests row that is either
-- not active (is_active = false) or not in a bookable state.
--
-- This is the canonical server-side enforcement for the is_active flag
-- introduced in migration 20260907000006. Client-side pre-checks in
-- checkout_service.dart surface a friendlier error message, but the trigger
-- ensures the invariant holds even if the client check is bypassed.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_check_custom_service_bookable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
BEGIN
  -- Only applies to booking_items that reference a custom service.
  IF NEW.custom_service_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Verify the custom service is active and in a bookable state.
  SELECT service_name INTO v_name
  FROM vendor_service_requests
  WHERE id             = NEW.custom_service_id
    AND is_active      = TRUE
    AND request_type   = 'new_service'
    AND status         IN ('completed', 'pending_deletion');

  IF NOT FOUND THEN
    -- Fetch the name for the error message even if not active.
    SELECT service_name INTO v_name
    FROM vendor_service_requests
    WHERE id = NEW.custom_service_id;

    RAISE EXCEPTION 'Custom service "%" is not currently available for booking.',
      COALESCE(v_name, 'Unknown service');
  END IF;

  RETURN NEW;
END;
$$;

-- Drop first in case the trigger already exists from a partial run.
DROP TRIGGER IF EXISTS trg_check_custom_service_bookable ON booking_items;

CREATE TRIGGER trg_check_custom_service_bookable
  BEFORE INSERT ON booking_items
  FOR EACH ROW
  EXECUTE FUNCTION fn_check_custom_service_bookable();
