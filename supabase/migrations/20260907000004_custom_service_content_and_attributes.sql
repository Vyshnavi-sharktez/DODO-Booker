-- ── Vendor Custom Service: Content and Attributes tabs ───────────────────────
--
-- 1. vendor_service_requests: adds the same content columns that catalog_nodes
--    carries so the Content tab in CustomServiceConfigDialog has a place to save.
--
-- 2. service_attributes: adds custom_service_id FK so the Attributes/Variants
--    tab can create attribute rows scoped to a vendor custom service without
--    touching catalog_nodes or the catalog tree.

-- ── 1. Content columns on vendor_service_requests ─────────────────────────────

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS included_items      JSONB NOT NULL DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS excluded_items      JSONB NOT NULL DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS before_after_pairs  JSONB NOT NULL DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS content_blocks      JSONB NOT NULL DEFAULT '[]';

-- ── 2. custom_service_id on service_attributes ────────────────────────────────

ALTER TABLE service_attributes
  ADD COLUMN IF NOT EXISTS custom_service_id UUID
    REFERENCES vendor_service_requests(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_service_attributes_custom_service_id
  ON service_attributes (custom_service_id)
  WHERE custom_service_id IS NOT NULL;
