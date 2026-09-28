-- Enable RLS on notifications + add SELECT policy.
--
-- Root cause: Supabase Realtime (v2.9+) requires RLS to be ENABLED on a table
-- and at least one matching SELECT policy before it will deliver any postgres_changes
-- events to subscribing clients. With RLS disabled, the realtime server silently
-- drops all events regardless of channel filters.
--
-- The existing INSERT and DELETE policies are already permissive (all roles).
-- The SELECT policy follows the same open pattern — access control is enforced
-- at the app level (admin panel login, customer phone auth), not at the DB level.

-- Step 1: add SELECT policy BEFORE enabling RLS so the enable is atomic
-- (no window where anon SELECT returns empty).
DROP POLICY IF EXISTS "Allow all select notifications" ON public.notifications;
CREATE POLICY "Allow all select notifications"
  ON public.notifications
  FOR SELECT
  TO anon, authenticated, service_role
  USING (true);

-- Step 2: enable RLS — now all three policies (INSERT, SELECT, DELETE) are active.
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
