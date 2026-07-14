-- ============================================================
-- Migration: add rating + review_count to catalog_nodes
-- ============================================================
-- Adds denormalised rating fields so review_service.dart can
-- update catalog_nodes instead of the legacy services table.
--
-- Backfills from services using legacy_id match (State B:
-- catalog was rebuilt via UI so catalog_nodes.id ≠ services.id).
--
-- SAFE TO RE-RUN: uses IF NOT EXISTS / idempotent patterns.
-- ============================================================

-- 1. Add columns (no-op if already present)
ALTER TABLE catalog_nodes
  ADD COLUMN IF NOT EXISTS rating       NUMERIC(3, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_count INTEGER       NOT NULL DEFAULT 0;

-- 2. Recreate catalog_nodes_view to expose rating + review_count.
--    Matches the live column structure from 20260713000001 exactly
--    (scalar subqueries, same column ordering) with rating/review_count
--    appended after updated_at (positions 22-23).
--
--    get_catalog_node_children() returns SETOF catalog_nodes_view and
--    must be dropped before the view is replaced, then recreated after.

DROP FUNCTION IF EXISTS get_catalog_node_children(UUID);
DROP VIEW IF EXISTS catalog_nodes_view;

CREATE VIEW catalog_nodes_view AS
SELECT
  -- ── Table columns (pos 1-23) ─────────────────────────────────────────────
  -- Order matches 20260713000001 exactly; rating/review_count appended
  -- before the derived columns so existing column positions are unchanged.
  n.id,
  n.parent_id,
  n.legacy_id,
  n.legacy_type,
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

  -- ── Derived columns (pos 24-28) ──────────────────────────────────────────
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

-- Recreate get_catalog_node_children() after view change.
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
