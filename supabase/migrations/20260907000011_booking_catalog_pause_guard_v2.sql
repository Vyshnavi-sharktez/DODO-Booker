-- ── Guard: block booking paused catalog services (relationship-scoped check) ──
--
-- Replaces fn_check_booking_item_active from migration 20260907000010.
-- Previous version only checked catalog_nodes.availability_status; when admin
-- pauses a service via a parent path, the status is stored on
-- catalog_node_relationships, not catalog_nodes. This version checks both.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_check_booking_item_active()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name         TEXT;
  v_is_active    BOOLEAN;
  v_avail_status TEXT;
  v_rel_status   TEXT;
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
    -- Catalog service: check node-scoped is_active + availability_status
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

    -- Also check relationship-scoped availability_status when parent is known.
    -- This catches pauses set via a specific parent path in the admin catalog.
    IF NEW.catalog_parent_node_id IS NOT NULL THEN
      SELECT availability_status INTO v_rel_status
      FROM   catalog_node_relationships
      WHERE  child_id  = NEW.service_id
        AND  parent_id = NEW.catalog_parent_node_id;

      IF FOUND AND COALESCE(v_rel_status, 'active') <> 'active' THEN
        RAISE EXCEPTION 'Service "%" is temporarily unavailable for booking.',
          COALESCE(v_name, 'Unknown service');
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_booking_item_active ON booking_items;

CREATE TRIGGER trg_check_booking_item_active
  BEFORE INSERT ON booking_items
  FOR EACH ROW
  EXECUTE FUNCTION fn_check_booking_item_active();
