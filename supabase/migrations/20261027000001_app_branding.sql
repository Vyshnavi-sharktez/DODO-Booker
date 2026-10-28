-- ── App Branding ──────────────────────────────────────────────────────────────
-- Stores the uploaded brand icon URL for each application.
--
-- IMPORTANT: Updating the icon_url here does NOT automatically update installed
-- mobile app launcher icons.  Those icons are compiled into the APK / IPA at
-- build time using flutter_launcher_icons.  A new build is required for the
-- change to appear on users' home screens.
--
-- The only icon that changes immediately (on next page load) is the Admin Panel
-- sidebar logo, which is loaded at runtime from this table.

-- ── Table ─────────────────────────────────────────────────────────────────────

CREATE TABLE app_branding (
  app_id       TEXT        PRIMARY KEY,
  display_name TEXT        NOT NULL,
  icon_url     TEXT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by   UUID        REFERENCES auth.users(id) ON DELETE SET NULL
);

COMMENT ON TABLE  app_branding IS
  'One row per application (customer_app, vendor_app, admin_panel). '
  'Stores the uploaded brand icon URL. Mobile entries require a rebuild to '
  'take effect as launcher icons; the admin_panel entry updates the sidebar logo immediately.';

-- Seed one row per application so the page always shows all three cards.
INSERT INTO app_branding (app_id, display_name) VALUES
  ('customer_app', 'Customer App'),
  ('vendor_app',   'Vendor App'),
  ('admin_panel',  'Admin Panel')
ON CONFLICT (app_id) DO NOTHING;

-- ── Trigger: auto-update updated_at / updated_by ──────────────────────────────

CREATE OR REPLACE FUNCTION fn_app_branding_stamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  NEW.updated_by := auth.uid();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_app_branding_stamp
  BEFORE UPDATE ON app_branding
  FOR EACH ROW EXECUTE FUNCTION fn_app_branding_stamp();

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE app_branding ENABLE ROW LEVEL SECURITY;

-- Public read: icon_url and display_name are brand assets, not sensitive data.
-- The storage bucket is already public; this lets Customer and Vendor apps
-- fetch the configured logo URL at runtime without admin credentials.
CREATE POLICY "app_branding_select_public"
  ON app_branding FOR SELECT
  USING (true);

-- Only active admins may write (UPDATE) branding rows.
-- INSERT / DELETE are not exposed: rows are seeded above and never removed.
CREATE POLICY "app_branding_update_admins"
  ON app_branding FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = true
    )
  );

-- ── Storage bucket ────────────────────────────────────────────────────────────
-- Public bucket for app branding assets.  2 MB limit; PNG / JPEG / WEBP only.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'app-branding',
  'app-branding',
  true,
  2097152,
  ARRAY['image/png', 'image/jpeg', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Public read (anyone can fetch the brand icon).
CREATE POLICY "app_branding_storage_select"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'app-branding');

-- Active admins may upload new objects.
CREATE POLICY "app_branding_storage_insert"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'app-branding'
    AND EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = true
    )
  );

-- Active admins may replace existing objects (upsert).
CREATE POLICY "app_branding_storage_update"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING  (bucket_id = 'app-branding')
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = true
    )
  );

-- Active admins may delete objects (e.g. when removing an icon).
CREATE POLICY "app_branding_storage_delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'app-branding'
    AND EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = true
    )
  );

-- ── Realtime ──────────────────────────────────────────────────────────────────
-- Publish row-level changes so Customer and Vendor apps receive the new
-- icon_url the moment an admin saves it — no app restart required.

ALTER PUBLICATION supabase_realtime ADD TABLE app_branding;
