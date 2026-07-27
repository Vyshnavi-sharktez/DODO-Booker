-- The vendor app reads from the settings table as the `anon` role (no Supabase
-- Auth session).  If RLS is enabled on this table — whether via the dashboard
-- or a future migration — the anon role must have a SELECT policy or every
-- fetchSubscriptionSettings() call returns an empty list and subscription_enabled
-- is treated as false, even though the value in the database is 'true'.
--
-- This migration:
--   1. Enables RLS (idempotent — no-op if already on).
--   2. Grants anon role SELECT (read-only public settings).
--   3. Grants authenticated role full access (admin panel writes).
--
-- Safe to re-run: DROP POLICY IF EXISTS + CREATE POLICY pattern.

ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "settings_anon_read" ON settings;
CREATE POLICY "settings_anon_read"
  ON settings FOR SELECT
  TO anon
  USING (true);

DROP POLICY IF EXISTS "settings_authenticated_all" ON settings;
CREATE POLICY "settings_authenticated_all"
  ON settings FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);
