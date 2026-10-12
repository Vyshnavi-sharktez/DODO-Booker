-- Enable Supabase Realtime for the three scheduling tables so that
-- AdminRealtimeSync can receive change events without a manual refresh.
ALTER PUBLICATION supabase_realtime ADD TABLE calendar_schedules;
ALTER PUBLICATION supabase_realtime ADD TABLE global_scheduling;
ALTER PUBLICATION supabase_realtime ADD TABLE service_scheduling;
