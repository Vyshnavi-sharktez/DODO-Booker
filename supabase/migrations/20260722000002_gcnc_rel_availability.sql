-- ============================================================
-- Migration: expose relationship-scoped availability in
--            get_catalog_node_children return set
-- ============================================================
-- Problem: the function previously returned SETOF catalog_nodes_view,
-- which only carries node-scoped availability_status.  Child list
-- badges in the customer app therefore could not distinguish:
--   • "Carpet Cleaning is unavailable everywhere" (node-scoped)
--   • "Carpet Cleaning is unavailable only under Parent A" (rel-scoped)
-- A shared node unavailable under Parent A must still appear normal
-- under Parent B.
--
-- Fix: change the return type to an explicit TABLE that appends
--   rel_availability_status    TEXT
--   rel_unavailability_message TEXT
-- carrying the availability values of the specific parent→child
-- relationship edge used for this query invocation.
--
-- Existing callers (Dart rpc() → List<Map>) are not broken: extra
-- columns are simply additional map keys.  The hidden-child filters
-- already present in 20260722000001 are preserved unchanged.
--
-- Column baseline: catalog_nodes_view after 20260722000001 has:
--   id, name, slug, description, image_url, icon_key, sort_order,
--   is_active, is_bookable, base_price, estimated_duration,
--   minimum_order_amount, loyalty_earn_enabled, loyalty_earn_rule,
--   loyalty_fixed_points, loyalty_earn_per_100, rating, review_count,
--   created_at, updated_at,
--   children_count, parent_name, parent_slug, parent_ids (TEXT[]),
--   is_root_node, availability_status, unavailability_message
-- ============================================================

DROP FUNCTION IF EXISTS get_catalog_node_children(UUID);

CREATE FUNCTION get_catalog_node_children(p_parent_id UUID)
RETURNS TABLE (
  -- catalog_nodes_view columns (matching 20260722000001 view order exactly)
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
  children_count         INTEGER,
  parent_name            TEXT,
  parent_slug            TEXT,
  parent_ids             TEXT[],
  is_root_node           BOOLEAN,
  availability_status    TEXT,
  unavailability_message TEXT,
  -- Relationship-scoped columns for this specific parent→child edge
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
