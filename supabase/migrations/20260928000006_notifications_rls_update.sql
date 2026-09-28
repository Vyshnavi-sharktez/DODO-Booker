-- Add UPDATE policy to notifications.
--
-- When RLS was enabled in 20260928000002, only SELECT/INSERT/DELETE policies
-- existed. Without an UPDATE policy, every markAsRead / markAsUnread /
-- bulkMarkAsRead call from the Flutter client silently updated 0 rows,
-- so notifications always came back as unread on the next open.

DROP POLICY IF EXISTS "Allow all update notifications" ON public.notifications;
CREATE POLICY "Allow all update notifications"
  ON public.notifications
  FOR UPDATE
  TO anon, authenticated, service_role
  USING (true)
  WITH CHECK (true);
