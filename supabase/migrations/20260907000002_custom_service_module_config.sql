-- ── Vendor Custom Service: Module Configuration ───────────────────────────────
--
-- Adds custom_service_id to catalog_node_configs so that admin can configure
-- Tax, Loyalty, Scheduling, Commission, Surge Fee, Preferred Vendors, and
-- Vendor Subscription modules for vendor custom services
-- (vendor_service_requests rows) independently of catalog_nodes.
--
-- Existing catalog-node config rows are completely unaffected.

ALTER TABLE catalog_node_configs
  ADD COLUMN IF NOT EXISTS custom_service_id UUID
    REFERENCES vendor_service_requests(id) ON DELETE CASCADE;

-- Index for fast lookup by (custom_service_id, module).
CREATE INDEX IF NOT EXISTS idx_catalog_node_configs_custom_service
  ON catalog_node_configs (custom_service_id, module)
  WHERE custom_service_id IS NOT NULL;

-- Unique: at most one config row per (custom_service_id, module).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename  = 'catalog_node_configs'
      AND indexname  = 'uidx_catalog_node_configs_custom_service_module'
  ) THEN
    CREATE UNIQUE INDEX uidx_catalog_node_configs_custom_service_module
      ON catalog_node_configs (custom_service_id, module)
      WHERE custom_service_id IS NOT NULL;
  END IF;
END;
$$;
