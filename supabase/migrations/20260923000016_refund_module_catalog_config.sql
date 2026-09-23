-- ─────────────────────────────────────────────────────────────────────────────
-- Add 'refund' and 'vendor_subscription' to catalog_node_configs.module CHECK.
--
-- 'vendor_subscription' was introduced in 20260728000001 but its CHECK entry
-- was inadvertently omitted.  Adding it here alongside 'refund' so the
-- constraint is consistent with all modules the admin panel supports.
--
-- Refund module JSONB shape:
--   { "refund_period_days": <integer> }
--
-- Interpretation: overrides the global default_refund_period_days setting for
-- any service in this catalog subtree.  The value is the number of days after
-- the booking's completed_at within which a customer may submit a refund request.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE catalog_node_configs
  DROP CONSTRAINT IF EXISTS catalog_node_configs_module_check;

ALTER TABLE catalog_node_configs
  ADD CONSTRAINT catalog_node_configs_module_check
  CHECK (module IN (
    'tax', 'loyalty', 'scheduling', 'commission',
    'surge', 'preferred_vendors', 'vendor_subscription',
    'refund'
  ));
