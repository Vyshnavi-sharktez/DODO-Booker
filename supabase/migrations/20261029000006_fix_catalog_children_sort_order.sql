-- Fix get_catalog_node_children sort order
--
-- Root cause: move_catalog_node and reposition_catalog_node both update
-- catalog_nodes.sort_order only. catalog_node_relationships.sort_order is
-- only written once at node creation and never kept in sync with admin moves.
--
-- The previous ORDER BY r.sort_order used the stale relationship value, so
-- customer-facing sub-service carousels ignored all admin reordering.
--
-- Fix: order by v.sort_order (catalog_nodes.sort_order via the view), which
-- is the single authoritative field that all admin sort operations update.

DROP FUNCTION IF EXISTS get_catalog_node_children(UUID);

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
    AND  COALESCE(r.availability_status, 'active') <> 'hidden'
    AND  COALESCE(v.availability_status, 'active') <> 'hidden'
  ORDER  BY v.sort_order ASC, v.name ASC;
$$;
