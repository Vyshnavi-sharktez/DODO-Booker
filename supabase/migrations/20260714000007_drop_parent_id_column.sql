-- Remove catalog_nodes.parent_id (deprecated since 20260713000001_catalog_multi_parent).
-- catalog_node_relationships is the sole source of truth for parent-child relationships.
-- All 137 rows have parent_id = NULL since that migration nulled every value.
-- No live function, trigger, or Dart code reads this column from the table or view.
--
-- Also corrects catalog_nodes_view.parent_ids from TEXT[] → UUID[] (the ::TEXT cast
-- was unnecessary; PostgREST serialises UUID[] identically in JSON).
--
-- Drop order: function → view → indexes → column → recreate view → recreate function.

DROP FUNCTION IF EXISTS get_catalog_node_children(UUID);
DROP VIEW  IF EXISTS catalog_nodes_view;

DROP INDEX IF EXISTS idx_catalog_nodes_parent_id;
DROP INDEX IF EXISTS idx_catalog_nodes_sort;

ALTER TABLE catalog_nodes DROP COLUMN IF EXISTS parent_id;

-- ── Rebuild catalog_nodes_view ────────────────────────────────────────────────
-- Identical to 20260714000006 except:
--   • n.parent_id removed
--   • parent_ids: array_agg(r.parent_id) with no ::TEXT cast → UUID[]
--   • COALESCE fallback changed to ARRAY[]::UUID[]

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

  (
    SELECT COUNT(*)::INTEGER
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes c ON c.id = r.child_id
    WHERE  r.parent_id = n.id
      AND  c.is_active = true
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
      SELECT array_agg(r.parent_id ORDER BY r.sort_order ASC, r.created_at ASC)
      FROM   catalog_node_relationships r
      WHERE  r.child_id = n.id
    ),
    ARRAY[]::UUID[]
  ) AS parent_ids,

  NOT EXISTS (
    SELECT 1
    FROM   catalog_node_relationships r
    WHERE  r.child_id = n.id
  ) AS is_root_node

FROM catalog_nodes n;

-- ── Recreate get_catalog_node_children ───────────────────────────────────────

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
  ORDER  BY r.sort_order ASC, v.name ASC;
$$;
