-- Service Charge module for catalog nodes.
-- Config stored in catalog_node_configs (module = 'service_charge', node-scoped).
-- Persisted on bookings as service_charge_amount.

-- ── 1. Add service_charge to module CHECK ─────────────────────────────────────

ALTER TABLE catalog_node_configs
  DROP CONSTRAINT IF EXISTS catalog_node_configs_module_check;

ALTER TABLE catalog_node_configs
  ADD CONSTRAINT catalog_node_configs_module_check
  CHECK (module IN (
    'tax', 'loyalty', 'scheduling', 'commission',
    'surge', 'preferred_vendors', 'vendor_subscription',
    'refund', 'service_charge'
  ));

-- ── 2. Add service_charge_amount to bookings ─────────────────────────────────

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS service_charge_amount NUMERIC(10,2) NOT NULL DEFAULT 0;
