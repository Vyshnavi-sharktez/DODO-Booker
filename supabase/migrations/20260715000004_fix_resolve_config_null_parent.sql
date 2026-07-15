-- Fix resolve_catalog_module_config: walk up when p_parent_id is NULL.
--
-- Previous behaviour: when p_parent_id = NULL (no navigation context) the
-- function checked only the service node and returned NULL immediately,
-- never reaching an ancestor that has a node-scoped config (e.g. the
-- "AC Services" category node).
--
-- New behaviour: when v_parent_id is NULL and the current node has exactly
-- one parent in the junction table, continue the walk using that parent.
-- If the node has zero parents (root) or multiple parents (shared/ambiguous),
-- the existing NULL-return semantics are preserved.

CREATE OR REPLACE FUNCTION resolve_catalog_module_config(
  p_module     TEXT,
  p_service_id UUID,
  p_parent_id  UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_rel_id      UUID;
  v_child_id    UUID := p_service_id;
  v_parent_id   UUID := p_parent_id;
  v_config      JSONB;
  v_rel_count   INT;
  v_next_id     UUID;
  v_next_parent UUID;
BEGIN
  -- Derive the direct relationship_id from (parent_id, service_id)
  IF v_parent_id IS NOT NULL THEN
    SELECT id
    INTO   v_rel_id
    FROM   catalog_node_relationships
    WHERE  parent_id = v_parent_id
      AND  child_id  = v_child_id;
    -- If not found (data inconsistency), v_rel_id stays NULL; walk continues
    -- using only node-scoped checks.
  END IF;

  LOOP
    -- A. Check relationship-scoped config for the current edge
    IF v_rel_id IS NOT NULL THEN
      SELECT config
      INTO   v_config
      FROM   catalog_node_configs
      WHERE  module          = p_module
        AND  relationship_id = v_rel_id
        AND  is_enabled      = true;
      IF FOUND THEN RETURN v_config; END IF;
    END IF;

    -- B. Check node-scoped config for the current child node
    SELECT config
    INTO   v_config
    FROM   catalog_node_configs
    WHERE  module          = p_module
      AND  node_id         = v_child_id
      AND  relationship_id IS NULL
      AND  is_enabled      = true;
    IF FOUND THEN RETURN v_config; END IF;

    -- No parent provided or end of walk.
    -- When no path context was given (v_parent_id is still NULL because
    -- p_parent_id was NULL), try to resolve the parent via the junction
    -- table.  Only proceed when there is exactly one unambiguous parent so
    -- we never silently pick an arbitrary ancestor for shared nodes.
    IF v_parent_id IS NULL THEN
      SELECT COUNT(*)
      INTO   v_rel_count
      FROM   catalog_node_relationships
      WHERE  child_id = v_child_id;

      IF v_rel_count <> 1 THEN RETURN NULL; END IF;

      -- Exactly one parent: resolve it and fall through to Move-Up below.
      -- v_rel_id stays NULL (no edge context → skip rel-scoped check next pass).
      SELECT parent_id
      INTO   v_parent_id
      FROM   catalog_node_relationships
      WHERE  child_id = v_child_id;
    END IF;

    -- Move up: previous parent becomes the new child to inspect
    v_child_id  := v_parent_id;
    v_rel_id    := NULL;
    v_parent_id := NULL;

    SELECT COUNT(*) INTO v_rel_count
    FROM   catalog_node_relationships
    WHERE  child_id = v_child_id;

    IF v_rel_count = 0 THEN
      -- Root node: check node-scoped config then stop
      SELECT config
      INTO   v_config
      FROM   catalog_node_configs
      WHERE  module          = p_module
        AND  node_id         = v_child_id
        AND  relationship_id IS NULL
        AND  is_enabled      = true;
      IF FOUND THEN RETURN v_config; END IF;
      RETURN NULL;

    ELSIF v_rel_count = 1 THEN
      -- Exactly one parent: unambiguous, continue walk
      SELECT id, parent_id
      INTO   v_next_id, v_next_parent
      FROM   catalog_node_relationships
      WHERE  child_id = v_child_id;
      v_rel_id    := v_next_id;
      v_parent_id := v_next_parent;

    ELSE
      -- Multiple parents: ambiguous ancestry.
      -- Check deliberate node-scoped config (set for all contexts), then stop.
      -- Never choose an arbitrary parent.
      SELECT config
      INTO   v_config
      FROM   catalog_node_configs
      WHERE  module          = p_module
        AND  node_id         = v_child_id
        AND  relationship_id IS NULL
        AND  is_enabled      = true;
      IF FOUND THEN RETURN v_config; END IF;
      RETURN NULL;
    END IF;
  END LOOP;
END;
$$;
