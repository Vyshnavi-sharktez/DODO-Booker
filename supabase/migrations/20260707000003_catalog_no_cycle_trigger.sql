-- ============================================================
-- Prevent circular parent-child relationships in catalog_nodes
-- ============================================================
-- A cycle (e.g. A → B → C → A) would cause infinite recursion
-- in any tree traversal (breadcrumbs, search, attribute inheritance).
-- This trigger fires BEFORE any UPDATE that changes parent_id and
-- raises an exception if the new parent is a descendant of the node
-- being moved, or if the node is being set as its own parent.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_catalog_nodes_no_cycle()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  cycle_found BOOLEAN;
BEGIN
  -- Only runs when parent_id actually changes.
  IF (OLD.parent_id IS NOT DISTINCT FROM NEW.parent_id) THEN
    RETURN NEW;
  END IF;

  -- A node cannot be its own parent.
  IF NEW.parent_id = NEW.id THEN
    RAISE EXCEPTION
      'catalog_node_cycle: node % cannot be its own parent.', NEW.id;
  END IF;

  -- Walk the ancestor chain of NEW.parent_id.
  -- If we encounter NEW.id, the proposed move would create a cycle.
  SELECT EXISTS (
    WITH RECURSIVE ancestors AS (
      -- Start from the proposed new parent and walk to the root.
      SELECT id, parent_id
      FROM   catalog_nodes
      WHERE  id = NEW.parent_id

      UNION ALL

      SELECT cn.id, cn.parent_id
      FROM   catalog_nodes cn
      JOIN   ancestors a ON cn.id = a.parent_id
    )
    SELECT 1 FROM ancestors WHERE id = NEW.id
  ) INTO cycle_found;

  IF cycle_found THEN
    RAISE EXCEPTION
      'catalog_node_cycle: cannot move node % under one of its own descendants.',
      NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- Fire only on UPDATE when parent_id changes — no overhead on INSERT or DELETE.
DROP TRIGGER IF EXISTS trg_catalog_nodes_no_cycle ON catalog_nodes;
CREATE TRIGGER trg_catalog_nodes_no_cycle
  BEFORE UPDATE OF parent_id ON catalog_nodes
  FOR EACH ROW EXECUTE FUNCTION fn_catalog_nodes_no_cycle();
