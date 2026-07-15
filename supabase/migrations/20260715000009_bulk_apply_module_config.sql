-- bulk_apply_module_config_to_subtree
--
-- Propagates a module config from a root catalog node to all reachable
-- descendants, respecting the path-isolation semantics of the resolver
-- (resolve_catalog_module_config).
--
-- Traversal rules — three categories of descendants:
--
--   Non-shared clean descendants (COUNT(parents in catalog) = 1):
--     The resolver can walk unambiguously from the descendant all the way to
--     the root.  Existing relationship-scoped and node-scoped configs for the
--     given module are DELETED, so the resolver falls through to root's config.
--
--   Shared boundary nodes (COUNT(parents) > 1, but reachable from root via a
--     path of exclusively non-shared intermediates):
--     The resolver finds the relationship-scoped config for the specific
--     in-subtree edge BEFORE walking further up.  A relationship-scoped config
--     is UPSERTED on that edge only.  The shared node's node-scoped config,
--     which serves other catalog paths, is NOT touched.
--
--   Descendants of shared boundary nodes:
--     Excluded from traversal.  The resolver stops at the shared intermediate
--     before reaching the root, so path-isolation is impossible for these nodes.
--     They are reported in skipped_count.
--
-- Safety guarantees:
--   • A shared node appearing under both "AC Services" and "Plumbing" receives
--     a relationship-scoped override ONLY on the edge that is within the
--     selected subtree.  The other edge and its node-scoped config are untouched.
--   • The root node's own config is NOT modified here; the caller saves it first
--     via the existing upsert path and passes the same config payload here.
--   • Only the specified module is affected; all other modules are unchanged.
--
-- Parameters:
--   p_root_node_id  catalog_node whose config is being propagated
--   p_module        'tax' | 'loyalty' | 'scheduling' | 'commission'
--   p_config        JSONB config payload (same shape the root's config was saved with)
--   p_is_enabled    is_enabled value to propagate
--
-- Returns one row: (deleted_count, upserted_count, skipped_count)
--   deleted_count   config rows removed from non-shared clean descendants
--   upserted_count  relationship-scoped configs set on shared boundary nodes
--   skipped_count   shared boundary nodes whose subtrees were not traversed

CREATE OR REPLACE FUNCTION bulk_apply_module_config_to_subtree(
  p_root_node_id  UUID,
  p_module        TEXT,
  p_config        JSONB,
  p_is_enabled    BOOLEAN
)
RETURNS TABLE(deleted_count INT, upserted_count INT, skipped_count INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_deleted      INT := 0;
  v_upserted     INT := 0;
  v_skipped      INT := 0;
  v_existing_id  UUID;
  v_row_count    INT;
  rec            RECORD;
BEGIN
  FOR rec IN
    WITH RECURSIVE subtree AS (
      -- Seed: every direct child relationship of the root node
      SELECT cnr.id AS rel_id, cnr.child_id AS node_id
      FROM   catalog_node_relationships cnr
      WHERE  cnr.parent_id = p_root_node_id

      UNION ALL

      -- Recurse only through non-shared nodes (parent count = 1).
      -- A shared node (>1 parents) terminates the path-clean traversal because
      -- the resolver stops there and cannot propagate the root config to
      -- descendants in a path-isolated way.
      SELECT cnr.id, cnr.child_id
      FROM   catalog_node_relationships cnr
      JOIN   subtree s ON cnr.parent_id = s.node_id
      WHERE  (SELECT COUNT(*)
              FROM   catalog_node_relationships
              WHERE  child_id = s.node_id) = 1
    )
    SELECT
      s.rel_id,
      s.node_id,
      (SELECT COUNT(*)
       FROM   catalog_node_relationships
       WHERE  child_id = s.node_id) > 1 AS is_shared
    FROM subtree s
  LOOP
    IF rec.is_shared THEN
      -- Shared boundary node: set a relationship-scoped config on this
      -- specific in-subtree edge so the resolver finds it (step A) before
      -- stopping at the shared node (step >1-parents).
      -- The shared node's node-scoped config is left untouched so other
      -- catalog paths continue to use their own inherited config.
      SELECT id INTO v_existing_id
      FROM   catalog_node_configs
      WHERE  module = p_module AND relationship_id = rec.rel_id;

      IF FOUND THEN
        UPDATE catalog_node_configs
        SET    config     = p_config,
               is_enabled = p_is_enabled,
               updated_at = now()
        WHERE  id = v_existing_id;
      ELSE
        INSERT INTO catalog_node_configs (module, relationship_id, config, is_enabled)
        VALUES (p_module, rec.rel_id, p_config, p_is_enabled);
      END IF;

      v_upserted := v_upserted + 1;
      -- This shared node's subtree is not traversed (excluded by the CTE WHERE
      -- clause); it is counted so the caller knows path-isolation was partial.
      v_skipped  := v_skipped  + 1;

    ELSE
      -- Non-shared clean descendant: remove per-module overrides so the
      -- resolver falls through the unambiguous single-parent chain to root.

      -- 1. Delete relationship-scoped config for this specific edge.
      DELETE FROM catalog_node_configs
      WHERE  module = p_module AND relationship_id = rec.rel_id;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      v_deleted := v_deleted + v_row_count;

      -- 2. Delete node-scoped config for this node (applies anywhere).
      DELETE FROM catalog_node_configs
      WHERE  module = p_module
        AND  node_id         = rec.node_id
        AND  relationship_id IS NULL;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      v_deleted := v_deleted + v_row_count;
    END IF;
  END LOOP;

  RETURN QUERY SELECT v_deleted, v_upserted, v_skipped;
END;
$$;
