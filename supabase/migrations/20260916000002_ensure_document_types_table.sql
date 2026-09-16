-- Ensures the document_types table exists with seed data and correct RLS.
--
-- Migration 20260623000003 defines this table but was never applied to the
-- current database.  This migration re-applies it idempotently so it can be
-- run safely whether or not the original migration was recorded as applied.
--
-- All statements use IF NOT EXISTS / ON CONFLICT DO NOTHING so running this
-- migration twice (or after 20260623000003) causes no errors.

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

-- Policies use DO blocks so they are skipped if they already exist.
DO $$
BEGIN
  CREATE POLICY "document_types: authenticated read"
    ON document_types FOR SELECT TO authenticated
    USING (is_active = TRUE);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "document_types: anon read"
    ON document_types FOR SELECT TO anon
    USING (is_active = TRUE);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
