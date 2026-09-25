-- Allow any role to delete notifications.
-- Mirrors the existing permissive INSERT policy ("Allow all insert notifications").
-- Both customer (anon) and vendor (authenticated) roles need DELETE access.
DROP POLICY IF EXISTS "Allow all delete notifications" ON public.notifications;
CREATE POLICY "Allow all delete notifications" ON public.notifications
  FOR DELETE USING (true);
