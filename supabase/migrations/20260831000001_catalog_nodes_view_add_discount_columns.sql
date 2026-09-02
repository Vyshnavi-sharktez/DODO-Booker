-- Add discount_type and discount_value to catalog_nodes_view and
-- get_catalog_node_children so the customer app can read them.
--
-- The columns were added to the base table in 20260829000002_add_item_discounts.sql
-- but the view enumerates columns explicitly, so it must be recreated.
-- Based on the definition last set in 20260829000001_catalog_nodes_mobile_image.sql.

DROP VIEW IF EXISTS catalog_nodes_view;

CREATE VIEW catalog_nodes_view AS
SELECT
  n.id,
  n.name,
  n.slug,
  n.description,
  n.image_url,
  n.mobile_image_url,
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
  n.included_items,
  n.excluded_items,
  n.before_after_pairs,
  n.content_blocks,
  n.discount_type,
  n.discount_value,
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


-- ── Refresh get_catalog_node_children ────────────────────────────────────────

DROP FUNCTION IF EXISTS get_catalog_node_children(UUID);

CREATE FUNCTION get_catalog_node_children(p_parent_id UUID)
RETURNS TABLE (
  id                     UUID,
  name                   TEXT,
  slug                   TEXT,
  description            TEXT,
  image_url              TEXT,
  mobile_image_url       TEXT,
  icon_key               TEXT,
  sort_order             INTEGER,
  is_active              BOOLEAN,
  is_bookable            BOOLEAN,
  base_price             NUMERIC,
  estimated_duration     INTEGER,
  minimum_order_amount   NUMERIC,
  loyalty_earn_enabled   BOOLEAN,
  loyalty_earn_rule      TEXT,
  loyalty_fixed_points   INTEGER,
  loyalty_earn_per_100   INTEGER,
  rating                 NUMERIC,
  review_count           INTEGER,
  created_at             TIMESTAMPTZ,
  updated_at             TIMESTAMPTZ,
  included_items         JSONB,
  excluded_items         JSONB,
  before_after_pairs     JSONB,
  content_blocks         JSONB,
  discount_type          TEXT,
  discount_value         NUMERIC,
  children_count         INTEGER,
  parent_name            TEXT,
  parent_slug            TEXT,
  parent_ids             TEXT[],
  is_root_node           BOOLEAN,
  availability_status    TEXT,
  unavailability_message TEXT,
  rel_availability_status    TEXT,
  rel_unavailability_message TEXT
)
LANGUAGE SQL
STABLE
AS $$
  SELECT
    v.id,
    v.name,
    v.slug,
    v.description,
    v.image_url,
    v.mobile_image_url,
    v.icon_key,
    v.sort_order,
    v.is_active,
    v.is_bookable,
    v.base_price,
    v.estimated_duration,
    v.minimum_order_amount,
    v.loyalty_earn_enabled,
    v.loyalty_earn_rule,
    v.loyalty_fixed_points,
    v.loyalty_earn_per_100,
    v.rating,
    v.review_count,
    v.created_at,
    v.updated_at,
    v.included_items,
    v.excluded_items,
    v.before_after_pairs,
    v.content_blocks,
    v.discount_type,
    v.discount_value,
    v.children_count,
    v.parent_name,
    v.parent_slug,
    v.parent_ids,
    v.is_root_node,
    v.availability_status,
    v.unavailability_message,
    r.availability_status    AS rel_availability_status,
    r.unavailability_message AS rel_unavailability_message
  FROM   catalog_node_relationships r
  JOIN   catalog_nodes_view v ON v.id = r.child_id
  WHERE  r.parent_id = p_parent_id
    AND  v.is_active = true
    AND  COALESCE(r.availability_status, 'active') <> 'hidden'
    AND  COALESCE(v.availability_status, 'active') <> 'hidden'
  ORDER  BY r.sort_order ASC, v.name ASC;
$$;

NOTIFY pgrst, 'reload schema';
