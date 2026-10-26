-- SMS Provider Configuration
-- Generic, extensible SMS provider configuration for OTP delivery via the
-- Supabase Auth Send SMS Hook.
--
-- Two tables:
--   sms_provider_configs    — non-secret config (is_enabled, provider_name,
--                             api_url, extra_config JSONB)
--   sms_provider_secrets    — secret references stored in Supabase Vault
--                             (pgsodium XSalsa20-Poly1305); plaintext never
--                             returned to the browser
--
-- Design decisions encoded here:
--   • Only one provider may be enabled at a time.  A BEFORE trigger
--     automatically clears is_enabled on all other rows when one is enabled,
--     preventing a split-brain state.
--   • Provider slugs are open-ended ('msg91', 'generic_http', etc.).
--     Adding a new provider requires no schema change — only a new admin-panel
--     ProviderDefinition and a seeded row.
--   • All authenticated RPCs require an active admin identity verified via
--     public.is_active_admin() (SECURITY DEFINER, BYPASSRLS).  This prevents
--     customer and vendor OTP-authenticated users from calling these RPCs, since
--     they are also in the "authenticated" role.
--   • This migration does NOT activate the Supabase Auth Send SMS Hook.
--     Hook activation is a separate, manual Dashboard step performed only after
--     end-to-end testing confirms the provider delivers OTPs correctly.
--   • The existing Twilio credentials and the current phone-auth flows in the
--     customer and vendor apps are completely unchanged.
--
-- Vault RPC pattern:
--   Mirrors whatsapp_config (20261016000004) and incorporates the orphan-safe
--   3-step upsert from 20260929000001 to handle the known pgsodium edge case
--   where vault.create_secret() succeeds internally but returns NULL.
--
-- RLS authorisation pattern:
--   Uses public.is_active_admin() (introduced in 20260927000007) throughout,
--   which runs SECURITY DEFINER / BYPASSRLS, avoiding the admin_users RLS
--   recursion that inline subqueries cause.

-- ── sms_provider_configs ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sms_provider_configs (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  provider      TEXT        NOT NULL UNIQUE,
  is_enabled    BOOLEAN     NOT NULL DEFAULT false,
  provider_name TEXT        NOT NULL DEFAULT '',
  api_url       TEXT        NOT NULL DEFAULT '',
  extra_config  JSONB       NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Keep updated_at current on every write.
CREATE OR REPLACE FUNCTION fn_sms_provider_configs_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sms_provider_configs_updated_at ON sms_provider_configs;
CREATE TRIGGER trg_sms_provider_configs_updated_at
  BEFORE UPDATE ON sms_provider_configs
  FOR EACH ROW EXECUTE FUNCTION fn_sms_provider_configs_updated_at();

-- Enforce "at most one active provider" invariant at the database level.
-- When any row's is_enabled is set to true, this trigger sets is_enabled = false
-- on every OTHER row that was previously true before the write completes.
-- This means the admin panel never needs to do a two-step "disable old, enable
-- new" dance — a single upsert with is_enabled = true is always safe.
CREATE OR REPLACE FUNCTION fn_sms_enforce_single_active_provider()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_enabled = true THEN
    UPDATE sms_provider_configs
    SET    is_enabled = false
    WHERE  provider <> NEW.provider
      AND  is_enabled = true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sms_single_active_provider ON sms_provider_configs;
CREATE TRIGGER trg_sms_single_active_provider
  BEFORE INSERT OR UPDATE OF is_enabled ON sms_provider_configs
  FOR EACH ROW EXECUTE FUNCTION fn_sms_enforce_single_active_provider();

ALTER TABLE sms_provider_configs ENABLE ROW LEVEL SECURITY;

-- Admin-only: read and write permitted only for active admin panel users.
-- We use public.is_active_admin() (SECURITY DEFINER / BYPASSRLS) rather than
-- an inline EXISTS(SELECT ... FROM admin_users ...) to avoid the RLS recursion
-- chain fixed in 20260927000007.
-- Customers and vendors authenticated via phone OTP are also in the
-- "authenticated" role and must be excluded, hence the admin check.
-- service_role bypasses RLS entirely — the send-sms Edge Function reads the
-- active provider config without requiring an explicit policy.
DROP POLICY IF EXISTS "sms_cfg_admin_all" ON sms_provider_configs;
CREATE POLICY "sms_cfg_admin_all"
  ON sms_provider_configs FOR ALL
  TO authenticated
  USING     (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- Seed MSG91 row (disabled by default).
-- Admin must configure api_key, template_id, sender_id and enable the provider
-- before the Send SMS Hook can use it.
INSERT INTO sms_provider_configs (provider, provider_name, api_url, extra_config)
VALUES (
  'msg91',
  'MSG91',
  'https://api.msg91.com/api/v5/otp',
  '{"template_id": "", "sender_id": ""}'
)
ON CONFLICT (provider) DO NOTHING;

-- ── sms_provider_secrets ──────────────────────────────────────────────────────
-- Stores Vault secret references only.  The decrypted value never leaves the
-- server and is never returned to the browser.

CREATE TABLE IF NOT EXISTS sms_provider_secrets (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  provider        TEXT        NOT NULL,
  secret_name     TEXT        NOT NULL,
  vault_secret_id UUID,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, secret_name)
);

CREATE OR REPLACE FUNCTION fn_sms_provider_secrets_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sms_provider_secrets_updated_at ON sms_provider_secrets;
CREATE TRIGGER trg_sms_provider_secrets_updated_at
  BEFORE UPDATE ON sms_provider_secrets
  FOR EACH ROW EXECUTE FUNCTION fn_sms_provider_secrets_updated_at();

ALTER TABLE sms_provider_secrets ENABLE ROW LEVEL SECURITY;

-- No SELECT, INSERT, UPDATE, or DELETE policy for authenticated.
-- → The browser can never read secret metadata or vault IDs.
-- → service_role bypasses RLS and is used by get_sms_secret_value (below).

-- ── SECURITY DEFINER RPCs ─────────────────────────────────────────────────────

-- upsert_sms_secret
-- ─────────────────
-- Admin panel calls this to write or replace a provider secret into Vault.
-- Runs SECURITY DEFINER (as postgres / superuser) — bypasses RLS on both
-- sms_provider_secrets and vault.*.
-- Returns void — the plaintext value is NEVER echoed back.
--
-- Orphan-safe 3-step upsert (mirrors 20260929000001):
--   Step 1 — if our table already tracks a vault_secret_id → update in place.
--   Step 2 — if vault.secrets has an entry by canonical name but our row has
--             vault_secret_id = NULL (prior create_secret returned NULL) →
--             re-link and update.
--   Step 3 — no vault entry at all → create fresh, raise on NULL return.
--
-- Vault name convention: 'sms:<provider>:<secret_name>'
-- e.g. 'sms:msg91:api_key'
CREATE OR REPLACE FUNCTION public.upsert_sms_secret(
  p_provider    TEXT,
  p_secret_name TEXT,
  p_value       TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_existing_vault_id UUID;
  v_orphan_vault_id   UUID;
  v_new_vault_id      UUID;
  v_vault_name        TEXT := 'sms:' || p_provider || ':' || p_secret_name;
BEGIN
  -- Require active admin identity (BYPASSRLS, no recursion risk).
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'admin authorisation required';
  END IF;

  IF p_value IS NULL OR length(trim(p_value)) = 0 THEN
    RAISE EXCEPTION 'secret value must not be empty';
  END IF;

  -- ── Step 1: check our table for a linked Vault entry ──────────────────────
  SELECT vault_secret_id INTO v_existing_vault_id
  FROM public.sms_provider_secrets
  WHERE provider = p_provider AND secret_name = p_secret_name;

  IF v_existing_vault_id IS NOT NULL THEN
    PERFORM vault.update_secret(v_existing_vault_id, p_value);
    UPDATE public.sms_provider_secrets
    SET    updated_at = now()
    WHERE  provider = p_provider AND secret_name = p_secret_name;
    RETURN;
  END IF;

  -- ── Step 2: detect orphaned Vault entry ───────────────────────────────────
  -- Covers the case where a prior vault.create_secret() created the entry in
  -- Vault but returned NULL, so our row stored vault_secret_id = NULL while a
  -- vault.secrets row with the canonical name already exists.
  SELECT id INTO v_orphan_vault_id
  FROM vault.secrets
  WHERE name = v_vault_name;

  IF v_orphan_vault_id IS NOT NULL THEN
    PERFORM vault.update_secret(v_orphan_vault_id, p_value);
    INSERT INTO public.sms_provider_secrets (provider, secret_name, vault_secret_id)
    VALUES (p_provider, p_secret_name, v_orphan_vault_id)
    ON CONFLICT (provider, secret_name) DO UPDATE SET
      vault_secret_id = EXCLUDED.vault_secret_id,
      updated_at      = now();
    RETURN;
  END IF;

  -- ── Step 3: no Vault entry exists — create fresh ──────────────────────────
  SELECT vault.create_secret(p_value, v_vault_name) INTO v_new_vault_id;

  IF v_new_vault_id IS NULL THEN
    RAISE EXCEPTION
      'vault.create_secret returned NULL for "%". '
      'Ensure the supabase_vault extension is enabled and pgsodium is initialised.',
      v_vault_name;
  END IF;

  INSERT INTO public.sms_provider_secrets (provider, secret_name, vault_secret_id)
  VALUES (p_provider, p_secret_name, v_new_vault_id)
  ON CONFLICT (provider, secret_name) DO UPDATE SET
    vault_secret_id = EXCLUDED.vault_secret_id,
    updated_at      = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_sms_secret(TEXT, TEXT, TEXT) TO authenticated;

-- sms_secret_is_set
-- ─────────────────
-- Returns true if a Vault-backed secret exists for this provider + secret_name.
-- Lets the admin UI display "Configured / Not set" without returning the value.
-- Requires active admin identity.
CREATE OR REPLACE FUNCTION public.sms_secret_is_set(
  p_provider    TEXT,
  p_secret_name TEXT
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'admin authorisation required';
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.sms_provider_secrets
    WHERE provider      = p_provider
      AND secret_name   = p_secret_name
      AND vault_secret_id IS NOT NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.sms_secret_is_set(TEXT, TEXT) TO authenticated;

-- get_sms_secret_value
-- ────────────────────
-- Decrypts and returns the Vault secret for a provider + secret_name.
-- Called exclusively by Edge Functions that hold a service_role JWT.
-- NEVER callable by the browser (anon or authenticated).
--
-- Two independent access-control layers:
--   Layer 1 (PostgreSQL GRANT): EXECUTE revoked from PUBLIC, granted only to
--            service_role.  anon and authenticated cannot call this function.
--   Layer 2 (Supabase JWT check): auth.role() verified inside the body.
--            Even if the GRANT were accidentally widened, the function refuses
--            any caller whose JWT role is not 'service_role'.
CREATE OR REPLACE FUNCTION public.get_sms_secret_value(
  p_provider    TEXT,
  p_secret_name TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_value TEXT;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Access denied: insufficient privileges';
  END IF;

  SELECT ds.decrypted_secret INTO v_value
  FROM public.sms_provider_secrets sps
  JOIN vault.decrypted_secrets      ds  ON ds.id = sps.vault_secret_id
  WHERE sps.provider    = p_provider
    AND sps.secret_name = p_secret_name;

  RETURN v_value;
END;
$$;

REVOKE ALL  ON FUNCTION public.get_sms_secret_value(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sms_secret_value(TEXT, TEXT) TO service_role;
