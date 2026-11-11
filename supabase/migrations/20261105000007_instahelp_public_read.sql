-- Allow customers (and unauthenticated users) to read active InstaHelp
-- configuration so the booking sheet can populate.
--
-- instahelp_modes      — originally had admin-only policy; no customer read
-- instahelp_durations  — same gap
--
-- instahelp_activities already has a read policy (auth.uid() IS NOT NULL)
-- added in migration 20261105000006, so no change needed there.
-- ─────────────────────────────────────────────────────────────────────────────

-- Modes: anyone can read active modes (catalog data, no PII)
DROP POLICY IF EXISTS "public_read_active_instahelp_modes" ON public.instahelp_modes;
CREATE POLICY "public_read_active_instahelp_modes"
  ON public.instahelp_modes FOR SELECT
  USING (is_active = TRUE);

-- Durations: anyone can read active durations for a given mode
DROP POLICY IF EXISTS "public_read_active_instahelp_durations" ON public.instahelp_durations;
CREATE POLICY "public_read_active_instahelp_durations"
  ON public.instahelp_durations FOR SELECT
  USING (is_active = TRUE);
