-- ============================================================
-- Per-node content fields: What's Included, What's Excluded,
-- Before & After image pairs.
--
-- Stored directly on catalog_nodes as JSONB — never inherited,
-- always scoped to the specific node the admin configured.
--
-- Schema:
--   included_items    : ["Display text", ...]
--   excluded_items    : ["Display text", ...]
--   before_after_pairs: [{"before_url":"...", "after_url":"..."}, ...]
--
-- The catalog_nodes_view is refreshed to expose these columns.
-- get_catalog_node_children is NOT updated — content fields are
-- only needed when a specific node is opened, not during navigation.
-- ============================================================

ALTER TABLE catalog_nodes
  ADD COLUMN IF NOT EXISTS included_items     JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS excluded_items     JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS before_after_pairs JSONB NOT NULL DEFAULT '[]'::jsonb;


-- ── Refresh catalog_nodes_view ───────────────────────────────────────────────
-- Column order: preserve all existing columns exactly, append the three new
-- ones before the computed columns so existing positional readers are safe.

DROP VIEW IF EXISTS catalog_nodes_view;

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
  -- New content columns
  n.included_items,
  n.excluded_items,
  n.before_after_pairs,
  -- Computed columns (unchanged logic from 20260722000001)
  (
    SELECT COUNT(*)::INTEGER
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes c ON c.id = r.child_id
    WHERE  r.parent_id = n.id
      AND  c.is_active = true
      AND  COALESCE(r.availability_status, 'active') <> 'hidden'
      AND  COALESCE(c.availability_status, 'active') <> 'hidden'
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
      SELECT array_agg(r.parent_id::TEXT ORDER BY r.sort_order ASC, r.created_at ASC)
      FROM   catalog_node_relationships r
      WHERE  r.child_id = n.id
    ),
    ARRAY[]::TEXT[]
  ) AS parent_ids,

  NOT EXISTS (
    SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = n.id
  ) AS is_root_node,

  n.availability_status,
  n.unavailability_message
FROM catalog_nodes n;

NOTIFY pgrst, 'reload schema';
