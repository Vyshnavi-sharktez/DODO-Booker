-- catalog_node_configs: per-relationship or per-node module configuration.
-- Supports Tax, Loyalty, Scheduling, Commission modules.
--
-- Two scope modes (exactly one must be set per row):
--   relationship-scoped: relationship_id IS NOT NULL, node_id IS NULL
--     Applies only when the customer accessed the child node via this specific
--     parent→child relationship. Never leaks to the same node accessed via a
--     different relationship.
--   node-scoped: node_id IS NOT NULL, relationship_id IS NULL
--     Applies to this node regardless of which parent it was accessed from.
--     Correct and deliberate for non-shared nodes and for cascade.
--
-- config JSONB shapes:
--   tax:        { tax_name, tax_type ('percentage'|'fixed'), tax_value }
--   loyalty:    { earn_enabled, earn_rule ('global'|'fixed'|'percentage'),
--                 fixed_points, earn_per_100 }
--   scheduling: { is_enabled, working_days (INT[]), max_bookings_per_slot,
--                 slots (TEXT[]) }
--   commission: { commission_type ('percentage'|'fixed'), commission_value }

CREATE TABLE catalog_node_configs (
  id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  module          TEXT    NOT NULL
                  CHECK (module IN ('tax', 'loyalty', 'scheduling', 'commission')),
  relationship_id UUID    REFERENCES catalog_node_relationships(id) ON DELETE CASCADE,
  node_id         UUID    REFERENCES catalog_nodes(id)              ON DELETE CASCADE,
  CONSTRAINT cnc_scope_check CHECK (
    (relationship_id IS NOT NULL AND node_id IS NULL) OR
    (relationship_id IS NULL     AND node_id IS NOT NULL)
  ),
  config          JSONB   NOT NULL DEFAULT '{}',
  is_enabled      BOOLEAN NOT NULL DEFAULT true,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_cnc_rel_module
  ON catalog_node_configs (module, relationship_id)
  WHERE relationship_id IS NOT NULL;

CREATE UNIQUE INDEX idx_cnc_node_module
  ON catalog_node_configs (module, node_id)
  WHERE node_id IS NOT NULL;

CREATE INDEX idx_cnc_rel  ON catalog_node_configs (relationship_id) WHERE relationship_id IS NOT NULL;
CREATE INDEX idx_cnc_node ON catalog_node_configs (node_id)         WHERE node_id         IS NOT NULL;

ALTER TABLE catalog_node_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cnc_anon_read"  ON catalog_node_configs FOR SELECT TO anon        USING (true);
CREATE POLICY "cnc_auth_all"   ON catalog_node_configs FOR ALL    TO authenticated USING (true) WITH CHECK (true);

-- ── resolve_catalog_module_config ─────────────────────────────────────────────
--
-- Walks the catalog hierarchy from the booked service toward the root, checking
-- for the most-specific applicable config.  Returns NULL when no scoped config
-- is found; callers fall back to their module-specific global table.
--
-- Resolution order at each level (most → least specific):
--   A. relationship-scoped config for the current edge (path-isolated)
--   B. node-scoped config for the current child node  (any context)
--   Move up to parent edge.  If the current node has:
--     0 parents → check node-scoped on root, return NULL
--     1 parent  → continue walk (unambiguous)
--     >1 parents → check node-scoped on this shared node, return NULL
--                  (never pick an arbitrary parent — stop here)
--
-- Parameters:
--   p_module     – 'tax' | 'loyalty' | 'scheduling' | 'commission'
--   p_service_id – catalog_node.id of the booked service (leaf)
--   p_parent_id  – catalog_node.id of the immediate parent through which the
--                  customer accessed the service; NULL = no path context

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

    -- No parent to walk toward
    IF v_parent_id IS NULL THEN RETURN NULL; END IF;

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
