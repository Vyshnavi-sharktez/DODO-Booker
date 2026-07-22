-- customer_reviews was omitted from the initial Realtime publication (00004).
-- Required for: customer submits review → admin panel updates automatically
-- without manual refresh.
--
-- The admin panel's AdminRealtimeSync subscribes to this table and calls
-- bookingsNotifierProvider.refresh() on INSERT/UPDATE/DELETE, which re-fetches
-- bookings with the joined customer_reviews data.

ALTER PUBLICATION supabase_realtime ADD TABLE customer_reviews;
