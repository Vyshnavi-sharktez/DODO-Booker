-- ── Guard: prevent booking inactive catalog services ─────────────────────────
--
-- Two changes:
--
-- 1. check_node_availability — add catalog_nodes.is_active check at every
--    node in the ancestor walk. A node with is_active = false returns
--    {status: 'unavailable'} regardless of availability_status. This fixes the
--    enforce_booking_location trigger on bookings (which calls this RPC) and
--    the client-side location availability pre-check.
--
-- 2. booking_items trigger — replace fn_check_custom_service_bookable (from
--    migration 20260907000008) with fn_check_booking_item_active, which guards
--    both custom service items (is_active on vendor_service_requests) AND
--    catalog service items (is_active on catalog_nodes).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Part 1: Update check_node_availability ────────────────────────────────────

DROP FUNCTION IF EXISTS check_node_availability(UUID, UUID, NUMERIC, NUMERIC);

CREATE FUNCTION check_node_availability(
  p_node_id   UUID,
  p_parent_id UUID,
  p_lat       NUMERIC DEFAULT NULL,
  p_lng       NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rel_id      UUID;
  v_child_id    UUID    := p_node_id;
  v_parent_id   UUID    := p_parent_id;
  v_is_active   BOOLEAN;
  v_status      TEXT;
  v_message     TEXT;
  v_rel_count   INT;
  v_next_id     UUID;
  v_next_parent UUID;
  v_loc_blocked BOOLEAN;
BEGIN
  -- Derive the initial relationship edge
  IF v_parent_id IS NOT NULL THEN
    SELECT id INTO v_rel_id
    FROM   catalog_node_relationships
    WHERE  parent_id = v_parent_id AND child_id = v_child_id;
  END IF;

  LOOP
    -- A. Relationship-scoped availability_status
    IF v_rel_id IS NOT NULL THEN
      SELECT availability_status, unavailability_message
      INTO   v_status, v_message
      FROM   catalog_node_relationships
      WHERE  id = v_rel_id;

      IF COALESCE(v_status, 'active') <> 'active' THEN
        RETURN jsonb_build_object('status', v_status, 'message', v_message);
      END IF;

      -- A2. Relationship-scoped location restriction
      IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        SELECT EXISTS (
          SELECT 1
          FROM   catalog_node_location_restrictions cnlr
          JOIN   service_availability_areas saa ON saa.id = cnlr.area_id
          WHERE  cnlr.relationship_id = v_rel_id
            AND  cnlr.node_id = v_child_id
            AND  saa.is_active = true
            AND  (
                   6371.0 * acos(
                     LEAST(1.0,
                       cos(radians(p_lat::FLOAT)) * cos(radians(saa.latitude::FLOAT))
                       * cos(radians(saa.longitude::FLOAT) - radians(p_lng::FLOAT))
                       + sin(radians(p_lat::FLOAT)) * sin(radians(saa.latitude::FLOAT))
                     )
                   )
                 ) <= saa.radius_km
        ) INTO v_loc_blocked;

        IF v_loc_blocked THEN
          RETURN jsonb_build_object(
            'status',  'unavailable',
            'message', 'This service is not available in your area.'
          );
        END IF;
      END IF;
    END IF;

    -- B. Node-scoped: is_active + availability_status
    SELECT is_active, availability_status, unavailability_message
    INTO   v_is_active, v_status, v_message
    FROM   catalog_nodes
    WHERE  id = v_child_id;

    -- Admin deactivated this node — treat as unavailable regardless of availability_status.
    IF NOT COALESCE(v_is_active, true) THEN
      RETURN jsonb_build_object(
        'status',  'unavailable',
        'message', 'This service is no longer available.'
      );
    END IF;

    IF COALESCE(v_status, 'active') <> 'active' THEN
      RETURN jsonb_build_object('status', v_status, 'message', v_message);
    END IF;

    -- B2. Node-scoped location restriction
    IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
      SELECT EXISTS (
        SELECT 1
        FROM   catalog_node_location_restrictions cnlr
        JOIN   service_availability_areas saa ON saa.id = cnlr.area_id
        WHERE  cnlr.node_id = v_child_id
          AND  cnlr.relationship_id IS NULL
          AND  saa.is_active = true
          AND  (
                 6371.0 * acos(
                   LEAST(1.0,
                     cos(radians(p_lat::FLOAT)) * cos(radians(saa.latitude::FLOAT))
                     * cos(radians(saa.longitude::FLOAT) - radians(p_lng::FLOAT))
                     + sin(radians(p_lat::FLOAT)) * sin(radians(saa.latitude::FLOAT))
                   )
                 )
               ) <= saa.radius_km
      ) INTO v_loc_blocked;

      IF v_loc_blocked THEN
        RETURN jsonb_build_object(
          'status',  'unavailable',
          'message', 'This service is not available in your area.'
        );
      END IF;
    END IF;

    -- No parent to walk toward: node is active
    IF v_parent_id IS NULL THEN
      RETURN jsonb_build_object('status', 'active', 'message', NULL::TEXT);
    END IF;

    -- Walk one level up
    v_child_id  := v_parent_id;
    v_rel_id    := NULL;
    v_parent_id := NULL;

    SELECT COUNT(*) INTO v_rel_count
    FROM   catalog_node_relationships
    WHERE  child_id = v_child_id;

    IF v_rel_count = 0 THEN
      -- Root ancestor: check is_active + node-scoped status + location
      SELECT is_active, availability_status, unavailability_message
      INTO   v_is_active, v_status, v_message
      FROM   catalog_nodes WHERE id = v_child_id;

      IF NOT COALESCE(v_is_active, true) THEN
        RETURN jsonb_build_object(
          'status',  'unavailable',
          'message', 'This service is no longer available.'
        );
      END IF;

      IF COALESCE(v_status, 'active') <> 'active' THEN
        RETURN jsonb_build_object('status', v_status, 'message', v_message);
      END IF;

      IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        SELECT EXISTS (
          SELECT 1
          FROM   catalog_node_location_restrictions cnlr
          JOIN   service_availability_areas saa ON saa.id = cnlr.area_id
          WHERE  cnlr.node_id = v_child_id
            AND  cnlr.relationship_id IS NULL
            AND  saa.is_active = true
            AND  (
                   6371.0 * acos(
                     LEAST(1.0,
                       cos(radians(p_lat::FLOAT)) * cos(radians(saa.latitude::FLOAT))
                       * cos(radians(saa.longitude::FLOAT) - radians(p_lng::FLOAT))
                       + sin(radians(p_lat::FLOAT)) * sin(radians(saa.latitude::FLOAT))
                     )
                   )
                 ) <= saa.radius_km
        ) INTO v_loc_blocked;

        IF v_loc_blocked THEN
          RETURN jsonb_build_object(
            'status',  'unavailable',
            'message', 'This service is not available in your area.'
          );
        END IF;
      END IF;

      RETURN jsonb_build_object('status', 'active', 'message', NULL::TEXT);

    ELSIF v_rel_count = 1 THEN
      -- Single parent: continue walking
      SELECT id, parent_id INTO v_next_id, v_next_parent
      FROM   catalog_node_relationships WHERE child_id = v_child_id;
      v_rel_id    := v_next_id;
      v_parent_id := v_next_parent;

    ELSE
      -- Shared ancestor (multiple parents): node-scoped check only, then stop
      SELECT is_active, availability_status, unavailability_message
      INTO   v_is_active, v_status, v_message
      FROM   catalog_nodes WHERE id = v_child_id;

      IF NOT COALESCE(v_is_active, true) THEN
        RETURN jsonb_build_object(
          'status',  'unavailable',
          'message', 'This service is no longer available.'
        );
      END IF;

      IF COALESCE(v_status, 'active') <> 'active' THEN
        RETURN jsonb_build_object('status', v_status, 'message', v_message);
      END IF;

      IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        SELECT EXISTS (
          SELECT 1
          FROM   catalog_node_location_restrictions cnlr
          JOIN   service_availability_areas saa ON saa.id = cnlr.area_id
          WHERE  cnlr.node_id = v_child_id
            AND  cnlr.relationship_id IS NULL
            AND  saa.is_active = true
            AND  (
                   6371.0 * acos(
                     LEAST(1.0,
                       cos(radians(p_lat::FLOAT)) * cos(radians(saa.latitude::FLOAT))
                       * cos(radians(saa.longitude::FLOAT) - radians(p_lng::FLOAT))
                       + sin(radians(p_lat::FLOAT)) * sin(radians(saa.latitude::FLOAT))
                     )
                   )
                 ) <= saa.radius_km
        ) INTO v_loc_blocked;

        IF v_loc_blocked THEN
          RETURN jsonb_build_object(
            'status',  'unavailable',
            'message', 'This service is not available in your area.'
          );
        END IF;
      END IF;

      RETURN jsonb_build_object('status', 'active', 'message', NULL::TEXT);
    END IF;
  END LOOP;
END;
$$;

-- ── Part 2: booking_items trigger — replace with comprehensive active guard ────
--
-- Drop the custom-service-only trigger from migration 20260907000008 and replace
-- with fn_check_booking_item_active, which guards both:
--   • custom_service_id → vendor_service_requests.is_active
--   • service_id        → catalog_nodes.is_active

DROP TRIGGER IF EXISTS trg_check_custom_service_bookable ON booking_items;
DROP FUNCTION IF EXISTS fn_check_custom_service_bookable();

CREATE OR REPLACE FUNCTION fn_check_booking_item_active()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name      TEXT;
  v_is_active BOOLEAN;
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
    -- Catalog service: must have is_active = true
    SELECT name, is_active
    INTO   v_name, v_is_active
    FROM   catalog_nodes
    WHERE  id = NEW.service_id;

    IF FOUND AND NOT COALESCE(v_is_active, true) THEN
      RAISE EXCEPTION 'Service "%" is no longer available for booking.',
        COALESCE(v_name, 'Unknown service');
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
