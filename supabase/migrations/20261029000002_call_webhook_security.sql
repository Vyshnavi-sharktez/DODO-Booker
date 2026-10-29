-- Migration: 20261029000002_call_webhook_security.sql
-- Harden exotel-webhook:
--   1. failure_reason column on call_sessions (stored for failed/missed calls)
--   2. Fast index on exotel_call_sid for webhook fallback lookup
--   3. call_session_recordings — admin-only table so recording URLs are NEVER
--      stored in call_sessions (which participants can read).
--      call_sessions.recording_status shows availability without exposing the URL.

-- ── 1. failure_reason on call_sessions ───────────────────────────────────────
ALTER TABLE public.call_sessions
  ADD COLUMN IF NOT EXISTS failure_reason TEXT;

-- ── 2. Index for webhook fallback lookup by exotel_call_sid ──────────────────
CREATE INDEX IF NOT EXISTS idx_call_sessions_exotel_call_sid
  ON public.call_sessions (exotel_call_sid)
  WHERE exotel_call_sid IS NOT NULL;

-- ── 3. Admin-only recording URL table ────────────────────────────────────────
-- Recording URLs (links to Exotel-hosted audio) are only accessible to admins.
-- Participants see recording_status ("pending"/"available") in call_sessions
-- but never the URL.  The webhook writes here; the admin monitoring panel reads
-- via a join.
CREATE TABLE IF NOT EXISTS public.call_session_recordings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id    UUID NOT NULL REFERENCES public.call_sessions(id) ON DELETE CASCADE,
  recording_url TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (session_id)
);

ALTER TABLE public.call_session_recordings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage call_session_recordings"
  ON public.call_session_recordings FOR ALL
  USING  (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- ── 4. Webhook token note ─────────────────────────────────────────────────────
-- The exotel-webhook Edge Function requires a secret token appended to the
-- StatusCallback URL (?token=<value>).  Set it via the admin Call Config page,
-- or directly:
--   SELECT upsert_call_secret('exotel', 'webhook_token', '<strong-random-token>');
-- Generate a suitable token with: openssl rand -hex 32
--
-- initiate-exotel-call reads this token from the vault and appends it to the
-- StatusCallback URL when placing each call.  If the token is not configured,
-- initiate-exotel-call logs a warning and uses the bare URL (Exotel still
-- delivers callbacks, but they will be rejected by the webhook with 503 until
-- the token is set).
