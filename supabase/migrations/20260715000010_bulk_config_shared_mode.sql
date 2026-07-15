-- Extends the bulk catalog config system with two modes:
--
--   'subtree_only' (default / existing behaviour)
--     Shared boundary nodes receive a RELATIONSHIP-SCOPED config on the specific
--     in-subtree edge so only that path is affected.  Other occurrences are unchanged.
--
--   'shared_everywhere'
--     Full subtree traversal with no shared-node stop.
--     1. All in-subtree relationship-scoped configs for the module are deleted first
--        so they cannot shadow the new global setting.
--     2. Shared descendants receive a NODE-SCOPED config that affects them wherever
--        they appear in the catalog.
--     3. Non-shared descendants still have their configs cleared to inherit from root.
--
-- Also adds count_shared_descendants_in_subtree(UUID) → INT which the client calls
-- before writing anything so it can show the mode-choice dialog only when needed.

-- ── Drop old 4-parameter version to avoid an ambiguous overload ───────────────
DROP FUNCTION IF EXISTS bulk_apply_module_config_to_subtree(UUID, TEXT, JSONB, BOOLEAN);

-- ── count_shared_descendants_in_subtree ──────────────────────────────────────
-- Returns the number of descendant catalog nodes that have more than one parent
-- (i.e. appear in multiple catalog trees).  Uses full traversal with UNION
-- deduplication so each node is counted once regardless of how many paths reach it.

CREATE OR REPLACE FUNCTION count_shared_descendants_in_subtree(p_root_node_id UUID)
RETURNS INT
LANGUAGE SQL
STABLE
SECURITY DEFINER
AS $$
  WITH RECURSIVE all_desc AS (
    SELECT cnr.child_id AS node_id
    FROM   catalog_node_relationships cnr
    WHERE  cnr.parent_id = p_root_node_id
    UNION
    SELECT cnr.child_id
    FROM   catalog_node_relationships cnr
    JOIN   all_desc s ON cnr.parent_id = s.node_id
  )
  SELECT COUNT(*)::INT
  FROM   all_desc
  WHERE  (SELECT COUNT(*)
          FROM   catalog_node_relationships
          WHERE  child_id = all_desc.node_id) > 1
$$;

-- ── bulk_apply_module_config_to_subtree (5-parameter version) ─────────────────
--
-- Parameters
--   p_root_node_id  catalog_node whose config is being propagated
--   p_module        'tax' | 'loyalty' | 'scheduling' | 'commission'
--   p_config        JSONB config payload matching the root's saved config shape
--   p_is_enabled    is_enabled value to propagate
--   p_mode          'subtree_only' (default) | 'shared_everywhere'
--
-- Returns one row: (deleted_count, upserted_count, skipped_count)
--   deleted_count   config rows deleted
--   upserted_count  configs upserted (rel-scoped for subtree_only; node-scoped for shared_everywhere)
--   skipped_count   shared boundary nodes whose subtrees were not traversed (subtree_only only)

CREATE OR REPLACE FUNCTION bulk_apply_module_config_to_subtree(
  p_root_node_id  UUID,
  p_module        TEXT,
  p_config        JSONB,
  p_is_enabled    BOOLEAN,
  p_mode          TEXT DEFAULT 'subtree_only'
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

  IF p_mode = 'shared_everywhere' THEN
    -- ── Mode: shared_everywhere ───────────────────────────────────────────────
    --
    -- Full traversal (UNION deduplicates per node_id — no shared-node stop).
    --
    -- Step 1: Delete ALL relationship-scoped configs for in-subtree edges so
    --         node-scoped configs set in step 2 are not shadowed by a previous
    --         'subtree_only' run on the same path.
    --
    -- Step 2: For each unique descendant:
    --   shared     → upsert NODE-SCOPED config  (affects the node on every path)
    --   non-shared → delete node-scoped config  (inherit from parent → root)

    WITH RECURSIVE all_desc AS (
      SELECT cnr.child_id AS node_id
      FROM   catalog_node_relationships cnr
      WHERE  cnr.parent_id = p_root_node_id
      UNION
      SELECT cnr.child_id
      FROM   catalog_node_relationships cnr
      JOIN   all_desc s ON cnr.parent_id = s.node_id
    ),
    subtree_node_ids AS (
      SELECT p_root_node_id AS node_id
      UNION ALL
      SELECT node_id FROM all_desc
    )
    DELETE FROM catalog_node_configs
    WHERE  module          = p_module
      AND  relationship_id IN (
             SELECT cnr.id
             FROM   catalog_node_relationships cnr
             WHERE  cnr.parent_id IN (SELECT node_id FROM subtree_node_ids)
               AND  cnr.child_id  IN (SELECT node_id FROM all_desc)
           );
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    v_deleted := v_deleted + v_row_count;

    FOR rec IN
      WITH RECURSIVE all_desc AS (
        SELECT cnr.child_id AS node_id
        FROM   catalog_node_relationships cnr
        WHERE  cnr.parent_id = p_root_node_id
        UNION
        SELECT cnr.child_id
        FROM   catalog_node_relationships cnr
        JOIN   all_desc s ON cnr.parent_id = s.node_id
      )
      SELECT
        node_id,
        (SELECT COUNT(*) FROM catalog_node_relationships WHERE child_id = all_desc.node_id) > 1
          AS is_shared
      FROM all_desc
    LOOP
      IF rec.is_shared THEN
        -- Upsert node-scoped config — applies to this node on every catalog path.
        SELECT id INTO v_existing_id
        FROM   catalog_node_configs
        WHERE  module          = p_module
          AND  node_id         = rec.node_id
          AND  relationship_id IS NULL;

        IF FOUND THEN
          UPDATE catalog_node_configs
          SET    config     = p_config,
                 is_enabled = p_is_enabled,
                 updated_at = now()
          WHERE  id = v_existing_id;
        ELSE
          INSERT INTO catalog_node_configs (module, node_id, config, is_enabled)
          VALUES (p_module, rec.node_id, p_config, p_is_enabled);
        END IF;
        v_upserted := v_upserted + 1;

      ELSE
        -- Non-shared: delete node-scoped config so it inherits from root.
        DELETE FROM catalog_node_configs
        WHERE  module          = p_module
          AND  node_id         = rec.node_id
          AND  relationship_id IS NULL;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        v_deleted := v_deleted + v_row_count;
      END IF;
    END LOOP;

  ELSE
    -- ── Mode: subtree_only (original behaviour, unchanged) ───────────────────
    --
    -- Traversal stops at shared nodes.  Shared boundary nodes (reachable via a
    -- clean non-shared path from root) receive a RELATIONSHIP-SCOPED config on
    -- the specific in-subtree edge only.  Other paths are untouched.

    FOR rec IN
      WITH RECURSIVE subtree AS (
        SELECT cnr.id AS rel_id, cnr.child_id AS node_id
        FROM   catalog_node_relationships cnr
        WHERE  cnr.parent_id = p_root_node_id

        UNION ALL

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
        (SELECT COUNT(*) FROM catalog_node_relationships WHERE child_id = s.node_id) > 1
          AS is_shared
      FROM subtree s
    LOOP
      IF rec.is_shared THEN
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
        v_skipped  := v_skipped  + 1;

      ELSE
        DELETE FROM catalog_node_configs
        WHERE  module = p_module AND relationship_id = rec.rel_id;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        v_deleted := v_deleted + v_row_count;

        DELETE FROM catalog_node_configs
        WHERE  module          = p_module
          AND  node_id         = rec.node_id
          AND  relationship_id IS NULL;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        v_deleted := v_deleted + v_row_count;
      END IF;
    END LOOP;
  END IF;

  RETURN QUERY SELECT v_deleted, v_upserted, v_skipped;
END;
$$;
