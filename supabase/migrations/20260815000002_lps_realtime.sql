-- Add landing_page_sections to the Supabase Realtime publication so
-- admin CMS publish events propagate to the customer app immediately.
--
-- CustomerRealtimeSync already subscribes to this table (realtime_sync.dart)
-- and calls _ref.invalidate(landingPageSectionsProvider) on any change.
-- Without being in the publication, those Postgres Changes events were
-- never fired, so display_order and publish state updates were invisible
-- to the customer app until a manual app restart.

ALTER PUBLICATION supabase_realtime ADD TABLE landing_page_sections;
