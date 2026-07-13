-- ============================================================
-- Remove unique constraint on catalog_nodes.slug
-- ============================================================
-- Allows multiple catalog items/services to share the same name
-- (and auto-generated slug) regardless of category.
-- IDs remain the sole unique identifier.
--
-- A non-unique index is kept so slug-based reads stay efficient.
--
-- SAFE TO RE-RUN: all statements are idempotent.
-- ============================================================

ALTER TABLE catalog_nodes
  DROP CONSTRAINT IF EXISTS catalog_nodes_slug_unique;

CREATE INDEX IF NOT EXISTS idx_catalog_nodes_slug
  ON catalog_nodes (slug);
