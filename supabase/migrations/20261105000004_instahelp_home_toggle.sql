-- Seed the instahelp home-screen visibility setting.
-- Also grant customers read access to settings rows they need.

INSERT INTO settings (setting_key, setting_value)
VALUES ('instahelp_home_enabled', 'true')
ON CONFLICT (setting_key) DO NOTHING;

-- Allow any authenticated user to read specific public settings keys.
-- Uses a permissive policy scoped to safe keys only.
DROP POLICY IF EXISTS "Public can read safe settings" ON settings;
CREATE POLICY "Public can read safe settings" ON settings
  FOR SELECT
  USING (setting_key IN ('instahelp_home_enabled'));
