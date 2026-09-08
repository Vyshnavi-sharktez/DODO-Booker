-- ── Fix resolve_catalog_module_config overload ambiguity ─────────────────────
--
-- Root cause:
--   Migration 20260908000002 used CREATE OR REPLACE with a 4-param signature
--   (p_module, p_service_id, p_parent_id, p_custom_service_id DEFAULT NULL).
--   Because the signature differs from the existing 3-param version, Postgres
--   created a SECOND overload rather than replacing the first.  Any 3-arg
--   caller now hits "function is not unique (42725)" because both overloads
--   are callable with 3 arguments.
--
-- Fix:
--   1. DROP the obsolete 3-param overload.
--   2. CREATE OR REPLACE the 4-param function with:
--        • the correct null-parent tree-walk body from 20260715000004
--        • the custom_service_id shortcut from 20260908000002
--   After this there is exactly one overload.  All existing 3-arg callers
--   (loyalty trigger, availability check, settlement RPCs, etc.) resolve
--   unambiguously to the 4-param function; the 4th arg defaults to NULL and
--   behaviour is identical to the old 3-param function.
-- ─────────────────────────────────────────────────────────────────────────────

-- Step 1: remove the old 3-param overload
DROP FUNCTION IF EXISTS resolve_catalog_module_config(TEXT, UUID, UUID);

-- Step 2: single canonical 4-param function
--   • p_custom_service_id is checked first (direct lookup, no tree walk).
--   • Falls through to the catalog-tree walk (with null-parent fix) otherwise.
CREATE OR REPLACE FUNCTION resolve_catalog_module_config(
  p_module            TEXT,
  p_service_id        UUID,
  p_parent_id         UUID,
  p_custom_service_id UUID DEFAULT NULL
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
  -- ── Custom-service shortcut ───────────────────────────────────────────────
  -- Direct lookup in catalog_node_configs by custom_service_id.
  -- Returns the config (or NULL when none configured) without any tree walk.
  -- Caller falls back to commission_rules when NULL is returned.
  IF p_custom_service_id IS NOT NULL THEN
    SELECT config
      INTO v_config
      FROM catalog_node_configs
     WHERE module            = p_module
       AND custom_service_id = p_custom_service_id
       AND is_enabled        = true;
    RETURN v_config;
  END IF;

  -- ── Catalog-tree walk (null-parent fix from 20260715000004) ──────────────

  IF v_parent_id IS NOT NULL THEN
    SELECT id
      INTO v_rel_id
      FROM catalog_node_relationships
     WHERE parent_id = v_parent_id
       AND child_id  = v_child_id;
  END IF;

  LOOP
    -- A. Relationship-scoped config for the current edge
    IF v_rel_id IS NOT NULL THEN
      SELECT config
        INTO v_config
        FROM catalog_node_configs
       WHERE module          = p_module
         AND relationship_id = v_rel_id
         AND is_enabled      = true;
      IF FOUND THEN RETURN v_config; END IF;
    END IF;

    -- B. Node-scoped config for the current child node
    SELECT config
      INTO v_config
      FROM catalog_node_configs
     WHERE module          = p_module
       AND node_id         = v_child_id
       AND relationship_id IS NULL
       AND is_enabled      = true;
    IF FOUND THEN RETURN v_config; END IF;

    -- When no path context was given (p_parent_id was NULL), try to resolve
    -- the parent via the junction table.  Only proceed when there is exactly
    -- one unambiguous parent so we never silently pick an arbitrary ancestor.
    IF v_parent_id IS NULL THEN
      SELECT COUNT(*)
        INTO v_rel_count
        FROM catalog_node_relationships
       WHERE child_id = v_child_id;

      IF v_rel_count <> 1 THEN RETURN NULL; END IF;

      SELECT parent_id
        INTO v_parent_id
        FROM catalog_node_relationships
       WHERE child_id = v_child_id;
    END IF;

    -- Move up: previous parent becomes the new child
    v_child_id  := v_parent_id;
    v_rel_id    := NULL;
    v_parent_id := NULL;

    SELECT COUNT(*) INTO v_rel_count
      FROM catalog_node_relationships
     WHERE child_id = v_child_id;

    IF v_rel_count = 0 THEN
      -- Root node: check node-scoped config then stop
      SELECT config
        INTO v_config
        FROM catalog_node_configs
       WHERE module          = p_module
         AND node_id         = v_child_id
         AND relationship_id IS NULL
         AND is_enabled      = true;
      IF FOUND THEN RETURN v_config; END IF;
      RETURN NULL;

    ELSIF v_rel_count = 1 THEN
      SELECT id, parent_id
        INTO v_next_id, v_next_parent
        FROM catalog_node_relationships
       WHERE child_id = v_child_id;
      v_rel_id    := v_next_id;
      v_parent_id := v_next_parent;

    ELSE
      -- Multiple parents: ambiguous — check deliberate node-scoped config only
      SELECT config
        INTO v_config
        FROM catalog_node_configs
       WHERE module          = p_module
         AND node_id         = v_child_id
         AND relationship_id IS NULL
         AND is_enabled      = true;
      IF FOUND THEN RETURN v_config; END IF;
      RETURN NULL;
    END IF;
  END LOOP;
END;
$$;
