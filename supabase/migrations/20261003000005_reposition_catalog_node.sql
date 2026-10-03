-- Migration: Direct position jump for catalog nodes
-- Adds reposition_catalog_node(p_node_id, p_parent_id, p_target_position) which
-- shifts all items between the old and new positions by one slot so the moved
-- item lands exactly at the requested 0-based position without any gaps or
-- duplicates.  Assumes sort_order values are already 0-based contiguous within
-- the scope (guaranteed by normalize_catalog_sort_order after every delete).

CREATE OR REPLACE FUNCTION reposition_catalog_node(
  p_node_id          UUID,
  p_parent_id        UUID,
  p_target_position  INT   -- 0-based target position within scope
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cur INT;
BEGIN
  SELECT sort_order INTO v_cur FROM catalog_nodes WHERE id = p_node_id;
  IF NOT FOUND OR v_cur = p_target_position THEN RETURN; END IF;

  IF p_parent_id IS NULL THEN
    -- ── Root scope ─────────────────────────────────────────────────────────────
    IF p_target_position < v_cur THEN
      -- Moving up: open a gap at target by shifting [target, cur) items down
      UPDATE catalog_nodes
         SET sort_order = sort_order + 1
       WHERE NOT EXISTS (
               SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = catalog_nodes.id
             )
         AND sort_order >= p_target_position
         AND sort_order <  v_cur
         AND id <> p_node_id;
    ELSE
      -- Moving down: close the gap by shifting (cur, target] items up
      UPDATE catalog_nodes
         SET sort_order = sort_order - 1
       WHERE NOT EXISTS (
               SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = catalog_nodes.id
             )
         AND sort_order >  v_cur
         AND sort_order <= p_target_position
         AND id <> p_node_id;
    END IF;

  ELSE
    -- ── Child scope under p_parent_id ──────────────────────────────────────────
    IF p_target_position < v_cur THEN
      UPDATE catalog_nodes
         SET sort_order = sort_order + 1
       WHERE id IN (
               SELECT cn.id
                 FROM catalog_nodes cn
                 JOIN catalog_node_relationships rel ON rel.child_id = cn.id
                WHERE rel.parent_id = p_parent_id
                  AND cn.sort_order >= p_target_position
                  AND cn.sort_order <  v_cur
                  AND cn.id <> p_node_id
             );
    ELSE
      UPDATE catalog_nodes
         SET sort_order = sort_order - 1
       WHERE id IN (
               SELECT cn.id
                 FROM catalog_nodes cn
                 JOIN catalog_node_relationships rel ON rel.child_id = cn.id
                WHERE rel.parent_id = p_parent_id
                  AND cn.sort_order >  v_cur
                  AND cn.sort_order <= p_target_position
                  AND cn.id <> p_node_id
             );
    END IF;
  END IF;

  -- Place the node at the requested position
  UPDATE catalog_nodes SET sort_order = p_target_position WHERE id = p_node_id;
END;
$$;
