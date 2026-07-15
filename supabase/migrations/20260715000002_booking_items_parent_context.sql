-- Add catalog_parent_node_id to booking_items.
--
-- Stores the catalog_node.id of the immediate parent through which the customer
-- accessed the service during browsing.  Used by resolve_catalog_module_config()
-- to determine the exact relationship edge and apply the correct path-scoped
-- Tax, Loyalty, Scheduling, or Commission configuration.
--
-- Nullable: existing booking_items rows get NULL, which causes the resolver to
-- skip relationship-scoped checks and fall back to node-scoped configs and the
-- module-specific global table.  Full backwards-compatibility guaranteed.

ALTER TABLE booking_items
  ADD COLUMN catalog_parent_node_id UUID
    REFERENCES catalog_nodes(id) ON DELETE SET NULL;

CREATE INDEX idx_bi_parent_node
  ON booking_items (catalog_parent_node_id)
  WHERE catalog_parent_node_id IS NOT NULL;
