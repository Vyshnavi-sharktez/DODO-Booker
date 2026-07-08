-- ============================================================
-- Add minimum_order_amount to catalog_nodes
-- ============================================================

ALTER TABLE catalog_nodes
  ADD COLUMN IF NOT EXISTS minimum_order_amount NUMERIC(10,2);
