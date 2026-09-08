-- ── Fix cnc_scope_check for custom_service_id scope ──────────────────────────
--
-- The original constraint required exactly one of (relationship_id, node_id)
-- to be set.  Migration 20260907000002 added custom_service_id as a third
-- valid scope key but did not update the constraint, causing all saves from
-- CustomServiceConfigDialog to fail with error 23514.
--
-- New rule: exactly one of the three scope columns must be non-null.

ALTER TABLE catalog_node_configs
  DROP CONSTRAINT IF EXISTS cnc_scope_check;

ALTER TABLE catalog_node_configs
  ADD CONSTRAINT cnc_scope_check CHECK (
    (relationship_id IS NOT NULL AND node_id IS NULL     AND custom_service_id IS NULL) OR
    (relationship_id IS NULL     AND node_id IS NOT NULL AND custom_service_id IS NULL) OR
    (relationship_id IS NULL     AND node_id IS NULL     AND custom_service_id IS NOT NULL)
  );
