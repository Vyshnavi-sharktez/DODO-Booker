-- Tax settings: singleton table for configurable tax calculation.
-- Customer app reads this at checkout instead of using the hardcoded 18% value.
-- Structure mirrors loyalty_settings / global_scheduling for consistent Dart parsing.

CREATE TABLE IF NOT EXISTS tax_settings (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled         BOOLEAN       NOT NULL DEFAULT true,
  tax_name           TEXT          NOT NULL DEFAULT 'GST',
  tax_type           TEXT          NOT NULL DEFAULT 'percentage'
                                   CHECK (tax_type IN ('percentage', 'fixed')),
  tax_value          NUMERIC(10,4) NOT NULL DEFAULT 18,
  apply_on_services  BOOLEAN       NOT NULL DEFAULT true,
  apply_on_addons    BOOLEAN       NOT NULL DEFAULT true,
  apply_on_packages  BOOLEAN       NOT NULL DEFAULT false,
  display_separately BOOLEAN       NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE tax_settings ENABLE ROW LEVEL SECURITY;

-- Admin full CRUD.
CREATE POLICY "authenticated_all" ON tax_settings
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Customer app reads tax settings before (or without) auth.
CREATE POLICY "anon_read" ON tax_settings
  FOR SELECT TO anon USING (true);

-- ── Seed row ──────────────────────────────────────────────────────────────────

-- Mirrors loyalty_settings / global_scheduling seed pattern.
-- Defaults to 18% GST on services and add-ons, displayed as a separate line.
INSERT INTO tax_settings (
  is_enabled, tax_name, tax_type, tax_value,
  apply_on_services, apply_on_addons, apply_on_packages,
  display_separately
)
SELECT true, 'GST', 'percentage', 18, true, true, false, true
WHERE NOT EXISTS (SELECT 1 FROM tax_settings);
