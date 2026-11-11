-- Allow customers (and unauthenticated users) to read active InstaHelp
-- activity groups so the customer_app booking modal can populate them.
--
-- customer_app authenticates customers via custom phone/OTP (stored in
-- SharedPreferences) rather than Supabase Auth, so auth.uid() is NULL.
-- Migration 20261105000006 created "read_active_instahelp_activities" with
-- USING (is_active = TRUE AND auth.uid() IS NOT NULL), which blocked all
-- customer_app reads on instahelp_activities while instahelp_modes and
-- instahelp_durations were opened up in 20261105000007.
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "read_active_instahelp_activities" ON public.instahelp_activities;
DROP POLICY IF EXISTS "public_read_active_instahelp_activities" ON public.instahelp_activities;

CREATE POLICY "public_read_active_instahelp_activities"
  ON public.instahelp_activities FOR SELECT
  USING (is_active = TRUE);

