-- Remove legacy_id and legacy_type from catalog_nodes and catalog_nodes_view.
-- The legacy categories/sub_categories/services tables were dropped in 000004.
-- These columns are no longer populated by any migration or runtime code:
--   - 1 of 137 rows has values (stale backfill data pointing to a deleted row)
--   - No live RPC, function, or trigger references them
--   - Dart reads the field only in a removed debugPrint (also cleaned in this PR)
--
-- Drop order: function → view → index → columns → recreate view → recreate function.

DROP FUNCTION IF EXISTS get_catalog_node_children(UUID);
DROP VIEW  IF EXISTS catalog_nodes_view;
DROP INDEX IF EXISTS idx_catalog_nodes_legacy;

ALTER TABLE catalog_nodes
  DROP COLUMN IF EXISTS legacy_id,
  DROP COLUMN IF EXISTS legacy_type;

CREATE VIEW catalog_nodes_view AS
SELECT
  n.id,
  n.parent_id,
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
      SELECT array_agg(r.parent_id::TEXT
                       ORDER BY r.sort_order ASC, r.created_at ASC)
      FROM   catalog_node_relationships r
      WHERE  r.child_id = n.id
    ),
    ARRAY[]::TEXT[]
  ) AS parent_ids,

  NOT EXISTS (
    SELECT 1
    FROM   catalog_node_relationships r
    WHERE  r.child_id = n.id
  ) AS is_root_node

FROM catalog_nodes n;

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
