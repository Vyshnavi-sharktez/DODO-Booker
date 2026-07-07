-- Stores before/after service photos uploaded by vendors and DODO team members.
--
-- Auth architecture: the Vendor App uses a custom phone/OTP flow (vendor_dev_auth).
-- No Supabase Auth session is created — requests arrive with the publishable key,
-- which Supabase maps to the 'anon' PostgreSQL role. This is the same pattern used
-- by vendor-documents (working reference). All vendor-writable policies target 'anon'.

CREATE TABLE IF NOT EXISTS booking_images (
  id          UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  booking_id  UUID        NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  image_type  TEXT        NOT NULL CHECK (image_type IN ('before', 'after')),
  image_url   TEXT        NOT NULL,
  uploaded_by TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_booking_images_booking_id
  ON booking_images (booking_id);

CREATE INDEX IF NOT EXISTS idx_booking_images_booking_type
  ON booking_images (booking_id, image_type);

ALTER TABLE booking_images ENABLE ROW LEVEL SECURITY;

-- Vendor / DODO Team apps (publishable key → anon role, no Supabase Auth session)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'booking_images'
      AND policyname = 'anon can insert booking_images'
  ) THEN
    CREATE POLICY "anon can insert booking_images"
      ON booking_images FOR INSERT TO anon WITH CHECK (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'booking_images'
      AND policyname = 'anon can view booking_images'
  ) THEN
    CREATE POLICY "anon can view booking_images"
      ON booking_images FOR SELECT TO anon USING (true);
  END IF;
END $$;

-- Admin Panel (Supabase email/password auth → authenticated role)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'booking_images'
      AND policyname = 'authenticated can manage booking_images'
  ) THEN
    CREATE POLICY "authenticated can manage booking_images"
      ON booking_images FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ── Storage bucket ────────────────────────────────────────────────────────────
-- The bucket may already exist (created manually in the dashboard).
-- ON CONFLICT DO NOTHING makes this safe to re-run.

INSERT INTO storage.buckets (id, name, public)
VALUES ('booking-photos', 'booking-photos', true)
ON CONFLICT (id) DO NOTHING;

-- Allow vendor / DODO Team apps to upload (same role as vendor-documents bucket).
-- Uses IF NOT EXISTS so this can be re-run even if the policy already exists.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'anon can upload to booking-photos'
  ) THEN
    CREATE POLICY "anon can upload to booking-photos"
      ON storage.objects FOR INSERT TO anon
      WITH CHECK (bucket_id = 'booking-photos');
  END IF;
END $$;

-- Admin Panel can manage objects (view, delete, replace).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'authenticated can manage booking-photos objects'
  ) THEN
    CREATE POLICY "authenticated can manage booking-photos objects"
      ON storage.objects FOR ALL TO authenticated
      USING (bucket_id = 'booking-photos')
      WITH CHECK (bucket_id = 'booking-photos');
  END IF;
END $$;

-- Public read — no token needed to display photos in customer/admin UI.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'public can read booking-photos'
  ) THEN
    CREATE POLICY "public can read booking-photos"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'booking-photos');
  END IF;
END $$;
