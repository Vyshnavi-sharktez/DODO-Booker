-- ── Guard: prevent booking paused (availability_status != 'active') catalog services ──
--
-- Extends fn_check_booking_item_active (from migration 20260907000009) to also
-- check catalog_nodes.availability_status. Previously only is_active was checked;
-- a node soft-paused by admin (availability_status = 'unavailable') was still bookable.
-- ──────────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_check_booking_item_active()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name        TEXT;
  v_is_active   BOOLEAN;
  v_avail_status TEXT;
BEGIN
  IF NEW.custom_service_id IS NOT NULL THEN
    -- Custom service: must be active + in a bookable state
    SELECT service_name, is_active
    INTO   v_name, v_is_active
    FROM   vendor_service_requests
    WHERE  id           = NEW.custom_service_id
      AND  request_type = 'new_service'
      AND  status       IN ('completed', 'pending_deletion');

    IF NOT FOUND OR NOT COALESCE(v_is_active, false) THEN
      SELECT service_name INTO v_name
      FROM   vendor_service_requests WHERE id = NEW.custom_service_id;
      RAISE EXCEPTION 'Custom service "%" is not currently available for booking.',
        COALESCE(v_name, 'Unknown service');
    END IF;

  ELSIF NEW.service_id IS NOT NULL THEN
    -- Catalog service: must have is_active = true AND availability_status = 'active'
    SELECT name, is_active, availability_status
    INTO   v_name, v_is_active, v_avail_status
    FROM   catalog_nodes
    WHERE  id = NEW.service_id;

    IF FOUND THEN
      IF NOT COALESCE(v_is_active, true) THEN
        RAISE EXCEPTION 'Service "%" is no longer available for booking.',
          COALESCE(v_name, 'Unknown service');
      END IF;

      IF COALESCE(v_avail_status, 'active') <> 'active' THEN
        RAISE EXCEPTION 'Service "%" is temporarily unavailable for booking.',
          COALESCE(v_name, 'Unknown service');
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Re-create trigger (DROP + CREATE is idempotent; OR REPLACE above already updated the function)
DROP TRIGGER IF EXISTS trg_check_booking_item_active ON booking_items;

CREATE TRIGGER trg_check_booking_item_active
  BEFORE INSERT ON booking_items
  FOR EACH ROW
  EXECUTE FUNCTION fn_check_booking_item_active();
