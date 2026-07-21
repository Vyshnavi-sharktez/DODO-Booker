-- ============================================================
-- Migration: catalog node availability (3-state per path)
-- ============================================================
-- Adds availability_status + unavailability_message to both
-- catalog_node_relationships (relationship-scoped) and catalog_nodes
-- (node-scoped / global override).
--
-- Availability resolution (check_node_availability RPC):
--   For a given (node, parentId) pair, walk the ancestry path in the
--   same way resolve_catalog_module_config does:
--     A. Check relationship-scoped availability for this (parent→child) edge.
--     B. Check node-scoped availability for the child node.
--     Stop walking at shared nodes (>1 parent) — those use node-scoped only.
--   Returns JSONB: {"status": "active"|"unavailable"|"hidden", "message": text|null}
--
-- Hierarchy semantics:
--   • relationship-scoped: affects ONLY the path through this parent.
--     A shared node hidden under Parent A stays visible under Parent B.
--   • node-scoped: applies regardless of path (global for that node).
--
-- get_catalog_node_children updated to:
--   • Exclude children whose relationship to this parent is 'hidden'.
--   • Exclude children that are node-scoped 'hidden'.
--
-- catalog_nodes_view updated to:
--   • Fix children_count: excludes relationship-hidden AND node-hidden children.
--   • Expose n.availability_status and n.unavailability_message.
--
-- View column baseline: 20260714000007_drop_parent_id_column.sql
--   parent_id, legacy_id, legacy_type were ALL dropped by prior migrations.
--   The correct column list starting from that migration is:
--     id, name, slug, description, image_url, icon_key, sort_order,
--     is_active, is_bookable, base_price, estimated_duration,
--     minimum_order_amount, loyalty_earn_enabled, loyalty_earn_rule,
--     loyalty_fixed_points, loyalty_earn_per_100, rating, review_count,
--     created_at, updated_at,
--     children_count, parent_name, parent_slug, parent_ids (TEXT[]), is_root_node
--
-- Constraints:
--   • Does NOT weaken existing RLS on catalog_nodes or catalog_node_relationships.
--   • check_node_availability is SECURITY DEFINER (same as resolve_catalog_module_config)
--     so the ancestry walk can see inactive ancestors without bypassing caller RLS.
-- ============================================================

-- 1. Add availability columns to catalog_node_relationships
ALTER TABLE catalog_node_relationships
  ADD COLUMN IF NOT EXISTS availability_status TEXT NOT NULL DEFAULT 'active'
    CHECK (availability_status IN ('active', 'unavailable', 'hidden')),
  ADD COLUMN IF NOT EXISTS unavailability_message TEXT;

-- 2. Add availability columns to catalog_nodes
ALTER TABLE catalog_nodes
  ADD COLUMN IF NOT EXISTS availability_status TEXT NOT NULL DEFAULT 'active'
    CHECK (availability_status IN ('active', 'unavailable', 'hidden')),
  ADD COLUMN IF NOT EXISTS unavailability_message TEXT;

-- 3. Drop dependent function before recreating the view
DROP FUNCTION IF EXISTS get_catalog_node_children(UUID);
DROP VIEW IF EXISTS catalog_nodes_view;

-- 4. Recreate catalog_nodes_view with availability columns and corrected children_count
--    Column order matches 20260714000007_drop_parent_id_column.sql exactly.
--    New columns (availability_status, unavailability_message) appended at the end.
CREATE VIEW catalog_nodes_view AS
SELECT
  n.id,
  n.name,
  n.slug,
  n.description,
  n.image_url,
  n.icon_key,
  n.sort_order,
  n.is_active,
  n.is_bookable,
  n.base_price,
  n.estimated_duration,
  n.minimum_order_amount,
  n.loyalty_earn_enabled,
  n.loyalty_earn_rule,
  n.loyalty_fixed_points,
  n.loyalty_earn_per_100,
  n.rating,
  n.review_count,
  n.created_at,
  n.updated_at,

  -- children_count: exclude relationship-hidden and node-hidden children
  (
    SELECT COUNT(*)::INTEGER
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes c ON c.id = r.child_id
    WHERE  r.parent_id = n.id
      AND  c.is_active = true
      AND  COALESCE(r.availability_status, 'active') <> 'hidden'
      AND  COALESCE(c.availability_status, 'active') <> 'hidden'
  ) AS children_count,

  (
    SELECT p.name
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes p ON p.id = r.parent_id
    WHERE  r.child_id = n.id
    ORDER  BY r.sort_order ASC, r.created_at ASC
    LIMIT  1
  ) AS parent_name,

  (
    SELECT p.slug
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes p ON p.id = r.parent_id
    WHERE  r.child_id = n.id
    ORDER  BY r.sort_order ASC, r.created_at ASC
    LIMIT  1
  ) AS parent_slug,

  COALESCE(
    (
      SELECT array_agg(r.parent_id::TEXT ORDER BY r.sort_order ASC, r.created_at ASC)
      FROM   catalog_node_relationships r
      WHERE  r.child_id = n.id
    ),
    ARRAY[]::TEXT[]
  ) AS parent_ids,

  NOT EXISTS (
    SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = n.id
  ) AS is_root_node,

  -- New columns (appended to preserve existing column positions)
  n.availability_status,
  n.unavailability_message

FROM catalog_nodes n;

-- 5. Recreate get_catalog_node_children — excludes hidden children
CREATE OR REPLACE FUNCTION get_catalog_node_children(p_parent_id UUID)
RETURNS SETOF catalog_nodes_view
LANGUAGE SQL
STABLE
AS $$
  SELECT v.*
  FROM   catalog_node_relationships r
  JOIN   catalog_nodes_view v ON v.id = r.child_id
  WHERE  r.parent_id = p_parent_id
    AND  v.is_active = true
    AND  COALESCE(r.availability_status, 'active') <> 'hidden'
    AND  COALESCE(v.availability_status, 'active') <> 'hidden'
  ORDER  BY r.sort_order ASC, v.name ASC;
$$;

-- 6. check_node_availability RPC
--    Walks the catalog path from (p_node_id, p_parent_id) toward the root,
--    stopping at shared nodes (multiple parents), using the same algorithm as
--    resolve_catalog_module_config.
--
--    Returns JSONB with keys: "status" (text) and "message" (text|null).
--    "status" is one of: "active", "unavailable", "hidden".
--
--    When p_parent_id IS NULL (deep-link / root node):
--      • Skips the relationship-scoped check for the immediate edge.
--      • Only the node-scoped check for p_node_id applies; returns immediately.
--
--    SECURITY DEFINER: needed so the walk can read inactive ancestors
--    (is_active = false) that the caller (anon) cannot normally see.
CREATE OR REPLACE FUNCTION check_node_availability(
  p_node_id   UUID,
  p_parent_id UUID
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
BEGIN
  -- Derive the direct relationship_id for the initial edge
  IF v_parent_id IS NOT NULL THEN
    SELECT id INTO v_rel_id
    FROM   catalog_node_relationships
    WHERE  parent_id = v_parent_id AND child_id = v_child_id;
  END IF;

  LOOP
    -- A. Check relationship-scoped availability for this edge
    IF v_rel_id IS NOT NULL THEN
      SELECT availability_status, unavailability_message
      INTO   v_status, v_message
      FROM   catalog_node_relationships
      WHERE  id = v_rel_id;

      IF COALESCE(v_status, 'active') <> 'active' THEN
        RETURN jsonb_build_object('status', v_status, 'message', v_message);
      END IF;
    END IF;

    -- B. Check node-scoped availability for the current node
    SELECT availability_status, unavailability_message
    INTO   v_status, v_message
    FROM   catalog_nodes
    WHERE  id = v_child_id;

    IF COALESCE(v_status, 'active') <> 'active' THEN
      RETURN jsonb_build_object('status', v_status, 'message', v_message);
    END IF;

    -- Stop if no parent to continue walking toward
    IF v_parent_id IS NULL THEN
      RETURN jsonb_build_object('status', 'active', 'message', NULL::TEXT);
    END IF;

    -- Move one level up the path
    v_child_id  := v_parent_id;
    v_rel_id    := NULL;
    v_parent_id := NULL;

    SELECT COUNT(*) INTO v_rel_count
    FROM   catalog_node_relationships
    WHERE  child_id = v_child_id;

    IF v_rel_count = 0 THEN
      -- Reached a root node: check its node-scoped status and stop
      SELECT availability_status, unavailability_message
      INTO   v_status, v_message
      FROM   catalog_nodes WHERE id = v_child_id;
      IF COALESCE(v_status, 'active') <> 'active' THEN
        RETURN jsonb_build_object('status', v_status, 'message', v_message);
      END IF;
      RETURN jsonb_build_object('status', 'active', 'message', NULL::TEXT);

    ELSIF v_rel_count = 1 THEN
      -- Single parent: continue walking
      SELECT id, parent_id INTO v_next_id, v_next_parent
      FROM   catalog_node_relationships WHERE child_id = v_child_id;
      v_rel_id    := v_next_id;
      v_parent_id := v_next_parent;

    ELSE
      -- Shared node (multiple parents): check node-scoped only, then stop
      SELECT availability_status, unavailability_message
      INTO   v_status, v_message
      FROM   catalog_nodes WHERE id = v_child_id;
      IF COALESCE(v_status, 'active') <> 'active' THEN
        RETURN jsonb_build_object('status', v_status, 'message', v_message);
      END IF;
      RETURN jsonb_build_object('status', 'active', 'message', NULL::TEXT);
    END IF;
  END LOOP;
END;
$$;
