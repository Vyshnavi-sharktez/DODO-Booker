-- Commission Rules: per-vendor, per-category, or global platform commission.
-- Priority at resolution time: vendor > category > global.

CREATE TABLE commission_rules (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_type        TEXT NOT NULL CHECK (rule_type IN ('global', 'category', 'vendor')),
  target_id        UUID NULL,           -- NULL for global; category/vendor id otherwise
  commission_type  TEXT NOT NULL DEFAULT 'percentage'
                   CHECK (commission_type IN ('percentage', 'fixed')),
  commission_value NUMERIC(10,4) NOT NULL DEFAULT 0,
  is_enabled       BOOLEAN NOT NULL DEFAULT true,
  notes            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Exactly one global row
CREATE UNIQUE INDEX commission_rules_global_unique
  ON commission_rules (rule_type)
  WHERE target_id IS NULL;

-- One scoped rule per (rule_type, target_id) pair
CREATE UNIQUE INDEX commission_rules_scoped_unique
  ON commission_rules (rule_type, target_id)
  WHERE target_id IS NOT NULL;

ALTER TABLE commission_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated admin access to commission_rules"
  ON commission_rules FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- Seed default global rule: 10% platform commission
INSERT INTO commission_rules (rule_type, target_id, commission_type, commission_value, is_enabled, notes)
VALUES ('global', NULL, 'percentage', 10.0, true, 'Default platform commission');
