-- ============================================================
-- Migration: catalog node location restrictions
-- ============================================================
-- Adds location-wise availability for catalog nodes.
-- Admin can disable a catalog item in specific Service Availability Areas
-- without affecting other areas or other catalog paths.
--
-- Design mirrors the existing availability system:
--   • relationship_id IS NULL   → node-scoped (root nodes, global for that node)
--   • relationship_id IS NOT NULL → relationship-scoped (path-specific, same as
--     the existing rel-scoped availability_status pattern)
--
-- Hierarchy: check_node_availability already walks the ancestry path checking
-- availability_status at each edge and node. This migration extends that walk to
-- also check location restrictions at each step using the same Haversine formula
-- as is_location_serviceable().
--
-- Backward compatibility:
--   check_node_availability gains two optional parameters (p_lat, p_lng DEFAULT NULL).
--   Existing callers that pass only (p_node_id, p_parent_id) continue to work
--   unchanged — location checks are skipped when p_lat IS NULL.
-- ============================================================

-- 1. Location restrictions table
CREATE TABLE catalog_node_location_restrictions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  node_id         UUID NOT NULL REFERENCES catalog_nodes(id) ON DELETE CASCADE,
  relationship_id UUID           REFERENCES catalog_node_relationships(id) ON DELETE CASCADE,
  area_id         UUID NOT NULL REFERENCES service_availability_areas(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Unique constraint: node-scoped (no relationship)
CREATE UNIQUE INDEX uq_cnlr_node
  ON catalog_node_location_restrictions (node_id, area_id)
  WHERE relationship_id IS NULL;

-- Unique constraint: relationship-scoped
CREATE UNIQUE INDEX uq_cnlr_rel
  ON catalog_node_location_restrictions (relationship_id, area_id)
  WHERE relationship_id IS NOT NULL;

CREATE INDEX idx_cnlr_node      ON catalog_node_location_restrictions (node_id);
CREATE INDEX idx_cnlr_rel       ON catalog_node_location_restrictions (relationship_id)
  WHERE relationship_id IS NOT NULL;

ALTER TABLE catalog_node_location_restrictions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cnlr_anon_read"  ON catalog_node_location_restrictions
  FOR SELECT TO anon         USING (true);
CREATE POLICY "cnlr_auth_read"  ON catalog_node_location_restrictions
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "cnlr_auth_write" ON catalog_node_location_restrictions
  FOR ALL    TO authenticated USING (true) WITH CHECK (true);

-- 2. Replace check_node_availability with location-aware version.
--    New signature adds optional p_lat / p_lng (DEFAULT NULL).
--    Existing callers are unaffected; location checks are skipped when both are NULL.
DROP FUNCTION IF EXISTS check_node_availability(UUID, UUID);

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
  v_child_id    UUID := p_node_id;
  v_parent_id   UUID := p_parent_id;
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

    -- B. Node-scoped availability_status
    SELECT availability_status, unavailability_message
    INTO   v_status, v_message
    FROM   catalog_nodes
    WHERE  id = v_child_id;

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
      -- Reached a root ancestor: check node-scoped status
      SELECT availability_status, unavailability_message
      INTO   v_status, v_message
      FROM   catalog_nodes WHERE id = v_child_id;

      IF COALESCE(v_status, 'active') <> 'active' THEN
        RETURN jsonb_build_object('status', v_status, 'message', v_message);
      END IF;

      -- Root ancestor: check node-scoped location restriction
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
      SELECT availability_status, unavailability_message
      INTO   v_status, v_message
      FROM   catalog_nodes WHERE id = v_child_id;

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

-- 3. Server-side booking enforcement
-- BEFORE INSERT trigger on bookings so a direct API insert cannot bypass location
-- restrictions. Two cases:
--   a) No coordinates on the booking row: block if any restriction exists for the
--      service — eligibility cannot be verified without coordinates.
--   b) Coordinates present: re-run check_node_availability (node-scoped; p_parent_id
--      is not available at the booking row level, so relationship-scoped restrictions
--      are enforced client-side only).
-- Only fires on INSERT; existing bookings are unaffected.
CREATE FUNCTION enforce_booking_location()
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

CREATE TRIGGER trg_enforce_booking_location
  BEFORE INSERT ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION enforce_booking_location();
