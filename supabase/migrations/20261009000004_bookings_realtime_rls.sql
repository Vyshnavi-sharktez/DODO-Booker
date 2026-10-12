-- Enable RLS on bookings for Supabase Realtime v2 compatibility.
--
-- Supabase Realtime (v2.9+) silently drops postgres_changes events for tables
-- where RLS is not enabled. This is the same issue that was fixed for the
-- notifications table in 20260928000002_notifications_rls_select.sql.
--
-- A single permissive ALL policy exactly replicates the previous no-RLS
-- behaviour. Security enforcement is at the application layer (admin JWT,
-- customer phone auth, vendor JWT), not at the DB layer — consistent with
-- the pattern used throughout this project.

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all access bookings" ON public.bookings;
CREATE POLICY "Allow all access bookings"
  ON public.bookings
  FOR ALL
  TO anon, authenticated, service_role
  USING (true)
  WITH CHECK (true);
