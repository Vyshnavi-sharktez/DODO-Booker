-- Replaces the hardcoded DocumentType enum in vendor_app.
-- Admin can add, rename, or deactivate document types from the Admin Panel
-- without requiring a vendor app code change or redeployment.

CREATE TABLE IF NOT EXISTS document_types (
  id          TEXT        PRIMARY KEY,
  label       TEXT        NOT NULL,
  icon_key    TEXT        NOT NULL DEFAULT 'description_outlined',
  is_required BOOLEAN     NOT NULL DEFAULT FALSE,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INT         NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO document_types (id, label, icon_key, is_required, sort_order) VALUES
  ('aadhaar_card',     'Aadhaar Card',     'credit_card_outlined',   TRUE,  1),
  ('pan_card',         'PAN Card',         'perm_identity_outlined', TRUE,  2),
  ('gst_certificate',  'GST Certificate',  'receipt_long_outlined',  FALSE, 3),
  ('business_license', 'Business License', 'store_outlined',         FALSE, 4),
  ('other',            'Other',            'description_outlined',   FALSE, 99)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE document_types ENABLE ROW LEVEL SECURITY;

-- Vendors (authenticated) can read active types to populate the upload dialog.
CREATE POLICY "document_types: authenticated read"
  ON document_types FOR SELECT TO authenticated
  USING (is_active = TRUE);

-- Anon read allows the vendor app to read types even before full auth is resolved.
CREATE POLICY "document_types: anon read"
  ON document_types FOR SELECT TO anon
  USING (is_active = TRUE);
