-- Enable Supabase Realtime on tables that need cross-app synchronisation.
-- The anon role already has SELECT on catalog/config tables (public data).
-- Admin-panel subscribers use authenticated Supabase sessions.

ALTER PUBLICATION supabase_realtime ADD TABLE bookings;
ALTER PUBLICATION supabase_realtime ADD TABLE catalog_nodes;
ALTER PUBLICATION supabase_realtime ADD TABLE catalog_node_relationships;
ALTER PUBLICATION supabase_realtime ADD TABLE catalog_node_location_restrictions;
ALTER PUBLICATION supabase_realtime ADD TABLE catalog_node_configs;
ALTER PUBLICATION supabase_realtime ADD TABLE tax_settings;
ALTER PUBLICATION supabase_realtime ADD TABLE surge_fee_settings;
ALTER PUBLICATION supabase_realtime ADD TABLE loyalty_settings;
ALTER PUBLICATION supabase_realtime ADD TABLE banners;
