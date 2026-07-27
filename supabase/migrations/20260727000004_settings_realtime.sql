-- Add settings table to the Supabase Realtime publication so that the
-- vendor app can subscribe to settings changes and invalidate its local
-- cache when the admin updates a global setting (e.g. subscription_enabled).
--
-- The vendor app listens for UPDATE events on the settings table via
-- VendorRealtimeSync._settingsChannel and invalidates subscriptionSettingsProvider
-- when any row changes.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    -- Only add if not already a member of the publication.
    IF NOT EXISTS (
      SELECT 1
        FROM pg_publication_tables
       WHERE pubname   = 'supabase_realtime'
         AND tablename = 'settings'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE settings;
    END IF;
  END IF;
END;
$$;
