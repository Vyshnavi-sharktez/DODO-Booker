-- Storage buckets for admin-managed catalog images and user avatars.
-- Uses ON CONFLICT DO NOTHING so re-running this migration is safe.

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('catalog-images', 'catalog-images', true),
  ('avatars',        'avatars',        true),
  ('cms-media',      'cms-media',      true)
ON CONFLICT (id) DO NOTHING;

-- ── catalog-images ────────────────────────────────────────────────────────────
-- Authenticated users (admins via service-role or anon with session) can upload,
-- update, and delete. Everyone can read (images are public CDN URLs).

CREATE POLICY "catalog_images_insert"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'catalog-images');

CREATE POLICY "catalog_images_update"
  ON storage.objects FOR UPDATE TO authenticated
  USING     (bucket_id = 'catalog-images')
  WITH CHECK (bucket_id = 'catalog-images');

CREATE POLICY "catalog_images_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'catalog-images');

CREATE POLICY "catalog_images_select"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'catalog-images');

-- ── avatars ───────────────────────────────────────────────────────────────────
-- Any authenticated user (customer, vendor) can upload/update/delete their own
-- files. Admin also uses authenticated session when editing customer records.

CREATE POLICY "avatars_insert"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "avatars_update"
  ON storage.objects FOR UPDATE TO authenticated
  USING     (bucket_id = 'avatars')
  WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "avatars_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars');

CREATE POLICY "avatars_select"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'avatars');

-- ── cms-media ─────────────────────────────────────────────────────────────────
-- Already used by the CMS landing-page editor (section_edit_dialog.dart).
-- Policies added here in case the bucket was created manually without them.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'cms_media_insert'
  ) THEN
    EXECUTE 'CREATE POLICY "cms_media_insert"
      ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = ''cms-media'')';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'cms_media_update'
  ) THEN
    EXECUTE 'CREATE POLICY "cms_media_update"
      ON storage.objects FOR UPDATE TO authenticated
      USING      (bucket_id = ''cms-media'')
      WITH CHECK (bucket_id = ''cms-media'')';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'cms_media_delete'
  ) THEN
    EXECUTE 'CREATE POLICY "cms_media_delete"
      ON storage.objects FOR DELETE TO authenticated
      USING (bucket_id = ''cms-media'')';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'cms_media_select'
  ) THEN
    EXECUTE 'CREATE POLICY "cms_media_select"
      ON storage.objects FOR SELECT TO public
      USING (bucket_id = ''cms-media'')';
  END IF;
END $$;
