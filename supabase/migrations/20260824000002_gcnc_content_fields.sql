-- ============================================================
-- Add content fields to get_catalog_node_children RPC.
--
-- 20260824000001 added included_items, excluded_items, and
-- before_after_pairs to catalog_nodes and catalog_nodes_view,
-- but intentionally left the RPC unchanged.  This migration
-- adds those three JSONB columns so the customer modal
-- receives content data during normal category browsing.
-- ============================================================

DROP FUNCTION IF EXISTS get_catalog_node_children(UUID);

CREATE FUNCTION get_catalog_node_children(p_parent_id UUID)
RETURNS TABLE (
  id                     UUID,
  name                   TEXT,
  slug                   TEXT,
  description            TEXT,
  image_url              TEXT,
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
