-- service_faqs: per-service FAQ entries managed from the Admin Panel.
-- service_add_ons: per-service optional add-ons (separate from the global
--   commerce addons table which is used for cart-level promotions).

-- ── Service FAQs ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS service_faqs (
  id          UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  service_id  UUID        NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  question    TEXT        NOT NULL,
  answer      TEXT        NOT NULL,
  sort_order  INT         NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_service_faqs_service_id ON service_faqs (service_id);

ALTER TABLE service_faqs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_faqs: public read"
  ON service_faqs FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY "service_faqs: authenticated write"
  ON service_faqs FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ── Service Add-ons ───────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS service_add_ons (
  id          UUID           NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  service_id  UUID           NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  name        TEXT           NOT NULL,
  description TEXT,
  price       NUMERIC(10, 2) NOT NULL DEFAULT 0,
  is_active   BOOLEAN        NOT NULL DEFAULT TRUE,
  sort_order  INT            NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_service_add_ons_service_id ON service_add_ons (service_id);

ALTER TABLE service_add_ons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_add_ons: public read"
  ON service_add_ons FOR SELECT TO anon, authenticated
  USING (is_active = TRUE);

CREATE POLICY "service_add_ons: authenticated write"
  ON service_add_ons FOR ALL TO authenticated
  USING (true) WITH CHECK (true);
