-- Global Add-ons: add-ons that apply across all service categories/nodes.
-- An add-on with is_global = TRUE appears in every service's add-on list
-- without being assigned to any specific catalog_node_addons row.
-- De-duplication: if a global add-on is also directly assigned to a node
-- the RPC emits it only once (direct assignment wins for sort_order).

-- ── 1. Column ─────────────────────────────────────────────────────────────────

ALTER TABLE addons
  ADD COLUMN IF NOT EXISTS is_global BOOLEAN NOT NULL DEFAULT FALSE;

-- ── 2. Updated batch RPC ──────────────────────────────────────────────────────
-- Returns per-node addons: directly-assigned UNION global, de-duplicated.
-- DISTINCT ON (node_id, addon_id) keeps the directly-assigned row first
-- because NULL sort_order from global path is replaced by 999, so the
-- ORDER BY puts the lower directly-assigned sort_order first.

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
  WITH combined AS (
    -- Directly assigned addons (priority 1)
    SELECT
      cna.node_id,
      a.id,
      a.name,
      a.description,
      a.price,
      a.is_active,
      a.discount_type,
      a.discount_value,
      cna.sort_order,
      1 AS priority
    FROM  catalog_node_addons cna
    JOIN  addons a ON a.id = cna.addon_id
    WHERE cna.node_id = ANY(p_node_ids)
      AND a.is_active = TRUE

    UNION ALL

    -- Global addons applied to every requested node (priority 2)
    SELECT
      nid.node_id,
      a.id,
      a.name,
      a.description,
      a.price,
      a.is_active,
      a.discount_type,
      a.discount_value,
      999 AS sort_order,
      2   AS priority
    FROM  unnest(p_node_ids) AS nid(node_id)
    CROSS JOIN addons a
    WHERE a.is_global  = TRUE
      AND a.is_active  = TRUE
  ),
  ranked AS (
    SELECT *,
      ROW_NUMBER() OVER (
        PARTITION BY node_id, id
        ORDER BY priority ASC
      ) AS rn
    FROM combined
  )
  SELECT node_id, id, name, description, price, is_active,
         discount_type, discount_value, sort_order
  FROM  ranked
  WHERE rn = 1
  ORDER BY node_id, sort_order ASC, name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_service_addons_batch(UUID[])
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
