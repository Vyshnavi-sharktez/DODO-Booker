-- Add optional discount fields to catalog_nodes, service_attribute_options, and addons.
-- Mirrors the AMC discount pattern: discount_type ('percentage'|'flat') + discount_value.
-- discount_value = 0 means no discount (default).

ALTER TABLE catalog_nodes
  ADD COLUMN IF NOT EXISTS discount_type  TEXT           NOT NULL DEFAULT 'percentage',
  ADD COLUMN IF NOT EXISTS discount_value NUMERIC(10, 2) NOT NULL DEFAULT 0;

ALTER TABLE service_attribute_options
  ADD COLUMN IF NOT EXISTS discount_type  TEXT           NOT NULL DEFAULT 'percentage',
  ADD COLUMN IF NOT EXISTS discount_value NUMERIC(10, 2) NOT NULL DEFAULT 0;

ALTER TABLE addons
  ADD COLUMN IF NOT EXISTS discount_type  TEXT           NOT NULL DEFAULT 'percentage',
  ADD COLUMN IF NOT EXISTS discount_value NUMERIC(10, 2) NOT NULL DEFAULT 0;

-- Expose new columns through the catalog nodes view by refreshing it.
-- (The view uses SELECT * so the new columns are included automatically after ALTER.)
