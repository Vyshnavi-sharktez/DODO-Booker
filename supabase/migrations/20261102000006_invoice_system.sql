-- ── 1. Storage bucket for generated invoices (private) ────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'invoices',
  'invoices',
  false,
  10485760,
  ARRAY['application/pdf']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "invoices_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'invoices');

CREATE POLICY "invoices_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'invoices');

-- ── 2. Invoice config table (company branding burned into PDFs) ────────────────
CREATE TABLE IF NOT EXISTS invoice_config (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_name     TEXT        NOT NULL DEFAULT 'DODO BOOKER',
  company_tagline  TEXT        NOT NULL DEFAULT 'Home Services Platform',
  company_address  TEXT,
  company_gstin    TEXT,
  company_phone    TEXT,
  company_email    TEXT,
  logo_url         TEXT,
  invoice_prefix   TEXT        NOT NULL DEFAULT 'INV',
  footer_note      TEXT,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO invoice_config (company_name, company_tagline, invoice_prefix)
VALUES ('DODO BOOKER', 'Home Services Platform', 'INV')
ON CONFLICT DO NOTHING;

ALTER TABLE invoice_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invoice_config_authed_all"
  ON invoice_config FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY "invoice_config_anon_read"
  ON invoice_config FOR SELECT TO anon
  USING (true);

-- ── 3. Invoice number sequence + invoices table ────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS invoice_number_seq;

CREATE TABLE IF NOT EXISTS invoices (
  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id       UUID         NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
  invoice_number   TEXT         NOT NULL UNIQUE,
  pdf_path         TEXT         NOT NULL,
  -- Financial snapshot frozen at generation time (never updated)
  subtotal         NUMERIC(12,2),
  tax_amount       NUMERIC(12,2),
  discount_amount  NUMERIC(12,2),
  total_amount     NUMERIC(12,2),
  generated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  generated_by     TEXT         NOT NULL DEFAULT 'admin'
);

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invoices_authed_all"
  ON invoices FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ── 4. Invoice number generator ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION next_invoice_number(p_prefix TEXT DEFAULT 'INV')
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  seq_val BIGINT;
BEGIN
  seq_val := nextval('invoice_number_seq');
  RETURN p_prefix
    || '-' || to_char(now() AT TIME ZONE 'UTC', 'YYYYMM')
    || '-' || lpad(seq_val::TEXT, 5, '0');
END;
$$;
