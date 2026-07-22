-- Add notifications table to Supabase Realtime publication so vendor
-- notification INSERT events can be streamed to the vendor app.
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
