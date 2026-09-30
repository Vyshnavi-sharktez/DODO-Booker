-- Simplify addon assignment: addons belong only to bookable service nodes.
-- No inheritance, no parent-level addons, no override flag.
--
-- Removes:
--   catalog_nodes.addon_override column (inheritance control flag)
--   resolve_node_addons_batch()       (hierarchy-walking RPC)
--
-- Adds:
--   get_service_addons_batch()  (direct junction-table lookup, no hierarchy)

-- ── 1. Drop inheritance override flag ─────────────────────────────────────────

ALTER TABLE catalog_nodes DROP COLUMN IF EXISTS addon_override;

-- ── 2. Drop old hierarchy-walking RPC ─────────────────────────────────────────

DROP FUNCTION IF EXISTS resolve_node_addons_batch(UUID[]);

-- ── 3. Simple batch addon fetch — direct join, no hierarchy ───────────────────
-- Returns all active addons assigned directly to each node in p_node_ids.
-- node_id identifies which service the row belongs to (replaces source_node_id).

CREATE OR REPLACE FUNCTION get_service_addons_batch(p_node_ids UUID[])
RETURNS TABLE (
  node_id        UUID,
  id             UUID,
  name           TEXT,
  description    TEXT,
  price          NUMERIC,
  is_active      BOOLEAN,
  discount_type  TEXT,
  discount_value NUMERIC,
  sort_order     INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    cna.node_id,
    a.id,
    a.name,
    a.description,
    a.price,
    a.is_active,
    a.discount_type,
    a.discount_value,
    cna.sort_order
  FROM  catalog_node_addons cna
  JOIN  addons a ON a.id = cna.addon_id
  WHERE cna.node_id = ANY(p_node_ids)
    AND a.is_active = TRUE
  ORDER BY cna.sort_order ASC, a.name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_service_addons_batch(UUID[])
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
