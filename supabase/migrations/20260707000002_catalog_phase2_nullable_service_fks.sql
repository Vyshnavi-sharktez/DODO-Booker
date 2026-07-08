-- ============================================================
-- Phase 2: Make service_id nullable on catalog-adjacent tables
-- ============================================================
-- Nodes created through the new Catalog Tree UI have a node_id
-- but no corresponding row in the services table, so service_id
-- cannot be set. Making it nullable (while keeping the FK) lets
-- new catalog nodes own attributes without a legacy services row.

ALTER TABLE service_attributes
ALTER COLUMN service_id DROP NOT NULL;