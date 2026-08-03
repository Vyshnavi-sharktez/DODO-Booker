-- Grant authenticated role the same SELECT/INSERT/UPDATE access on
-- amc_pause_requests that anon already has.
--
-- The admin panel signs in with Supabase Auth, so its requests carry a user JWT
-- and PostgREST assigns them the 'authenticated' role. The original policies
-- were TO anon only, which caused the admin panel to see 0 rows.
--
-- Pattern matches amc_resume_requests (20260802000001).

DROP POLICY IF EXISTS "amc_pause_requests_anon_insert" ON public.amc_pause_requests;
DROP POLICY IF EXISTS "amc_pause_requests_anon_select" ON public.amc_pause_requests;
DROP POLICY IF EXISTS "amc_pause_requests_anon_update" ON public.amc_pause_requests;

CREATE POLICY "amc_pause_requests_anon_insert"
  ON public.amc_pause_requests FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

CREATE POLICY "amc_pause_requests_anon_select"
  ON public.amc_pause_requests FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "amc_pause_requests_anon_update"
  ON public.amc_pause_requests FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);
