ALTER TABLE invoice_config
  ADD COLUMN IF NOT EXISTS template_pdf_url  TEXT,
  ADD COLUMN IF NOT EXISTS template_pdf_name TEXT;
