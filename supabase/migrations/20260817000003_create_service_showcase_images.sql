-- Admin-curated photo showcase for customer-facing service pages.
-- References existing booking_images rows — no new uploads or storage.
-- Vendor upload flow and booking_images table are unchanged.

CREATE TABLE IF NOT EXISTS service_showcase_images (
  catalog_node_id  UUID        NOT NULL REFERENCES catalog_nodes(id)  ON DELETE CASCADE,
  booking_image_id UUID        NOT NULL REFERENCES booking_images(id) ON DELETE CASCADE,
  sort_order       INT         NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (catalog_node_id, booking_image_id)
);

CREATE INDEX IF NOT EXISTS idx_service_showcase_catalog_node
  ON service_showcase_images (catalog_node_id);

ALTER TABLE service_showcase_images ENABLE ROW LEVEL SECURITY;

-- Customer app uses the anon role (phone OTP, no Supabase Auth session).
-- Matches the service_faqs public-read pattern exactly.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'service_showcase_images'
      AND policyname = 'service_showcase_images: public read'
  ) THEN
    CREATE POLICY "service_showcase_images: public read"
      ON service_showcase_images FOR SELECT TO anon, authenticated
      USING (true);
  END IF;
END $$;

-- Admin Panel (Supabase email/password auth → authenticated role) manages curation.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'service_showcase_images'
      AND policyname = 'service_showcase_images: authenticated write'
  ) THEN
    CREATE POLICY "service_showcase_images: authenticated write"
      ON service_showcase_images FOR ALL TO authenticated
      USING (true) WITH CHECK (true);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
