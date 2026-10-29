-- Migration: 20261029000001_call_provider_config.sql
-- Replace mock call bridge with Exotel provider configuration and secure backend

-- ── 1. Call provider configuration table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.call_provider_configs (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider     TEXT NOT NULL UNIQUE DEFAULT 'exotel',
  is_enabled   BOOLEAN NOT NULL DEFAULT FALSE,
  account_sid  TEXT,
  exophone     TEXT,
  record_calls BOOLEAN NOT NULL DEFAULT TRUE,
  call_timeout_seconds INT NOT NULL DEFAULT 30,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 2. Vault-backed secrets table ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.call_provider_secrets (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider       TEXT NOT NULL,
  secret_name    TEXT NOT NULL,
  vault_secret_id UUID,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(provider, secret_name)
);

-- ── 3. RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.call_provider_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_provider_secrets  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage call_provider_configs"
  ON public.call_provider_configs FOR ALL
  USING (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- Secrets table never directly readable; only via SECURITY DEFINER RPCs
CREATE POLICY "No direct access to call_provider_secrets"
  ON public.call_provider_secrets FOR ALL
  USING (false);

-- ── 4. Seed default exotel row ────────────────────────────────────────────────
INSERT INTO public.call_provider_configs (provider, is_enabled)
VALUES ('exotel', false)
ON CONFLICT (provider) DO NOTHING;

-- ── 5. Upsert call secret (admin-only) ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.upsert_call_secret(
  p_provider    TEXT,
  p_secret_name TEXT,
  p_value       TEXT
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vault_id  UUID;
  v_secret_key TEXT;
BEGIN
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_secret_key := 'call:' || p_provider || ':' || p_secret_name;

  SELECT vault_secret_id INTO v_vault_id
  FROM public.call_provider_secrets
  WHERE provider = p_provider AND secret_name = p_secret_name;

  IF v_vault_id IS NULL THEN
    SELECT vault.create_secret(p_value, v_secret_key) INTO v_vault_id;
    INSERT INTO public.call_provider_secrets (provider, secret_name, vault_secret_id)
    VALUES (p_provider, p_secret_name, v_vault_id)
    ON CONFLICT (provider, secret_name) DO UPDATE
      SET vault_secret_id = EXCLUDED.vault_secret_id, updated_at = NOW();
  ELSE
    PERFORM vault.update_secret(v_vault_id, p_value);
    UPDATE public.call_provider_secrets
    SET updated_at = NOW()
    WHERE provider = p_provider AND secret_name = p_secret_name;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_call_secret FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_call_secret TO authenticated;

-- ── 6. Read call secret (service_role only) ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_call_secret_value(
  p_provider    TEXT,
  p_secret_name TEXT
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_vault_id UUID;
  v_value    TEXT;
BEGIN
  IF auth.role() != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT vault_secret_id INTO v_vault_id
  FROM public.call_provider_secrets
  WHERE provider = p_provider AND secret_name = p_secret_name;

  IF v_vault_id IS NULL THEN RETURN NULL; END IF;

  SELECT decrypted_secret INTO v_value
  FROM vault.decrypted_secrets
  WHERE id = v_vault_id;

  RETURN v_value;
END;
$$;

REVOKE ALL ON FUNCTION public.get_call_secret_value FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_call_secret_value TO service_role;

-- ── 7. Check if call secret is set (admin UI only, returns bool) ──────────────
CREATE OR REPLACE FUNCTION public.call_secret_is_set(
  p_provider    TEXT,
  p_secret_name TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.call_provider_secrets
    WHERE provider = p_provider AND secret_name = p_secret_name
      AND vault_secret_id IS NOT NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.call_secret_is_set FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.call_secret_is_set TO authenticated;

-- ── 8. Extend call_sessions with Exotel-specific columns ─────────────────────
ALTER TABLE public.call_sessions
  ADD COLUMN IF NOT EXISTS exotel_call_sid  TEXT,
  ADD COLUMN IF NOT EXISTS recording_url    TEXT,
  ADD COLUMN IF NOT EXISTS recording_status TEXT NOT NULL DEFAULT 'none'
    CHECK (recording_status IN ('none', 'pending', 'available', 'failed'));

-- ── 9. Fix RLS on call_sessions (was globally permissive) ────────────────────
DROP POLICY IF EXISTS "Allow public all access on call_sessions" ON public.call_sessions;

CREATE POLICY "Admins can manage call_sessions"
  ON public.call_sessions FOR ALL
  USING (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- Authenticated users can read sessions where they are a participant
CREATE POLICY "Participants can read own call sessions"
  ON public.call_sessions FOR SELECT
  USING (caller_id = auth.uid() OR callee_id = auth.uid());

-- ── 10. Add call.config permission ───────────────────────────────────────────
INSERT INTO public.permissions (name, description)
SELECT 'call.config', 'Manage call provider configuration'
WHERE NOT EXISTS (SELECT 1 FROM public.permissions WHERE name = 'call.config');

-- ── 11. Enable realtime for call_sessions (vendor/customer app dialogs) ───────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'call_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.call_sessions;
  END IF;
END $$;
