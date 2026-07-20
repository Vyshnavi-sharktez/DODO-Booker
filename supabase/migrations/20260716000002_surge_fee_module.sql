-- ── Surge Fee module ──────────────────────────────────────────────────────────
--
-- 1. Global surge_fee_settings singleton table.
-- 2. Add 'surge' to catalog_node_configs.module CHECK constraint so per-catalog
--    surge overrides are stored alongside tax / loyalty / etc.
-- 3. Add snapshot columns to bookings (name, type, value, computed amount).

-- ── 1. Global singleton table ──────────────────────────────────────────────────

CREATE TABLE surge_fee_settings (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled    BOOLEAN     NOT NULL DEFAULT false,
  surge_name    TEXT        NOT NULL DEFAULT 'Surge Fee',
  surge_type    TEXT        NOT NULL DEFAULT 'percentage'
                CHECK (surge_type IN ('percentage', 'fixed')),
  surge_value   NUMERIC(10,4) NOT NULL DEFAULT 0,
  description   TEXT,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE surge_fee_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sfs_anon_read"  ON surge_fee_settings FOR SELECT TO anon          USING (true);
CREATE POLICY "sfs_auth_all"   ON surge_fee_settings FOR ALL    TO authenticated  USING (true) WITH CHECK (true);

-- ── 2. Extend catalog_node_configs.module CHECK to include 'surge' ─────────────

ALTER TABLE catalog_node_configs
  DROP CONSTRAINT IF EXISTS catalog_node_configs_module_check;

ALTER TABLE catalog_node_configs
  ADD CONSTRAINT catalog_node_configs_module_check
  CHECK (module IN ('tax', 'loyalty', 'scheduling', 'commission', 'surge'));

-- ── 3. Surge fee snapshot columns on bookings ──────────────────────────────────

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS surge_fee_name   TEXT,
  ADD COLUMN IF NOT EXISTS surge_fee_type   TEXT,
  ADD COLUMN IF NOT EXISTS surge_fee_value  NUMERIC(10,4),
  ADD COLUMN IF NOT EXISTS surge_fee_amount NUMERIC(12,2);
