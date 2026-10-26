-- WhatsApp Provider Configuration
-- Two tables:
--   whatsapp_provider_configs  — non-secret config (enabled, provider name, API URL, extra_config)
--   whatsapp_provider_secrets  — secrets (api_key) stored in Supabase Vault
--
-- RLS design:
--   whatsapp_provider_configs:  authenticated read/write, no anon access
--   whatsapp_provider_secrets:  admin write-only via SECURITY DEFINER RPCs,
--                               service_role reads (edge functions bypass RLS)

-- ── whatsapp_provider_configs ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS whatsapp_provider_configs (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  provider      TEXT        NOT NULL UNIQUE,
  is_enabled    BOOLEAN     NOT NULL DEFAULT false,
  provider_name TEXT        NOT NULL DEFAULT '',
  api_url       TEXT        NOT NULL DEFAULT '',
  extra_config  JSONB       NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION fn_whatsapp_provider_configs_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_whatsapp_provider_configs_updated_at ON whatsapp_provider_configs;
CREATE TRIGGER trg_whatsapp_provider_configs_updated_at
  BEFORE UPDATE ON whatsapp_provider_configs
  FOR EACH ROW EXECUTE FUNCTION fn_whatsapp_provider_configs_updated_at();

ALTER TABLE whatsapp_provider_configs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "wpc_authenticated_all" ON whatsapp_provider_configs;
CREATE POLICY "wpc_authenticated_all"
  ON whatsapp_provider_configs FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

-- Seed Interakt row (disabled by default)
INSERT INTO whatsapp_provider_configs (provider, provider_name, api_url)
VALUES ('interakt', 'Interakt', 'https://api.interakt.ai/v1/public/message/')
ON CONFLICT (provider) DO NOTHING;

-- ── whatsapp_provider_secrets ─────────────────────────────────────────────────
-- Stores secrets in Supabase Vault (pgsodium XSalsa20-Poly1305).
-- The plaintext value is never returned to the browser.

CREATE TABLE IF NOT EXISTS whatsapp_provider_secrets (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  provider        TEXT        NOT NULL,
  secret_name     TEXT        NOT NULL,
  vault_secret_id UUID,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, secret_name)
);

CREATE OR REPLACE FUNCTION fn_whatsapp_provider_secrets_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_whatsapp_provider_secrets_updated_at ON whatsapp_provider_secrets;
CREATE TRIGGER trg_whatsapp_provider_secrets_updated_at
  BEFORE UPDATE ON whatsapp_provider_secrets
  FOR EACH ROW EXECUTE FUNCTION fn_whatsapp_provider_secrets_updated_at();

ALTER TABLE whatsapp_provider_secrets ENABLE ROW LEVEL SECURITY;

-- No SELECT policy for authenticated → browser can never read secrets.
-- service_role bypasses RLS → edge functions can SELECT via get_whatsapp_secret_value.

-- ── SECURITY DEFINER RPCs ─────────────────────────────────────────────────────

-- upsert_whatsapp_secret: admin panel calls this to save a secret into Vault.
-- Runs SECURITY DEFINER (postgres role), bypasses RLS. Returns void — value never echoed.
CREATE OR REPLACE FUNCTION upsert_whatsapp_secret(
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
  v_new_vault_id      UUID;
  v_vault_name        TEXT := 'whatsapp:' || p_provider || ':' || p_secret_name;
BEGIN
  SELECT vault_secret_id INTO v_existing_vault_id
  FROM whatsapp_provider_secrets
  WHERE provider = p_provider AND secret_name = p_secret_name;

  IF v_existing_vault_id IS NOT NULL THEN
    PERFORM vault.update_secret(v_existing_vault_id, p_value);
    UPDATE whatsapp_provider_secrets
    SET updated_at = now()
    WHERE provider = p_provider AND secret_name = p_secret_name;
  ELSE
    v_new_vault_id := vault.create_secret(p_value, v_vault_name);
    INSERT INTO whatsapp_provider_secrets (provider, secret_name, vault_secret_id)
    VALUES (p_provider, p_secret_name, v_new_vault_id)
    ON CONFLICT (provider, secret_name)
    DO UPDATE SET
      vault_secret_id = EXCLUDED.vault_secret_id,
      updated_at      = now();
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_whatsapp_secret(TEXT, TEXT, TEXT) TO authenticated;

-- whatsapp_secret_is_set: returns true if a Vault secret exists for this provider+name.
-- Lets the admin UI show "Configured / Not set" without reading the value.
CREATE OR REPLACE FUNCTION whatsapp_secret_is_set(
  p_provider    TEXT,
  p_secret_name TEXT
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM whatsapp_provider_secrets
    WHERE provider      = p_provider
      AND secret_name   = p_secret_name
      AND vault_secret_id IS NOT NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION whatsapp_secret_is_set(TEXT, TEXT) TO authenticated;

-- get_whatsapp_secret_value: decrypts and returns the vault secret.
-- Called exclusively by Edge Functions using the service_role JWT.
-- Access control — two independent layers:
--   Layer 1 (PostgreSQL): EXECUTE revoked from PUBLIC, granted only to service_role.
--   Layer 2 (Supabase JWT): auth.role() check inside the function body.
CREATE OR REPLACE FUNCTION get_whatsapp_secret_value(
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
  FROM whatsapp_provider_secrets wps
  JOIN vault.decrypted_secrets ds ON ds.id = wps.vault_secret_id
  WHERE wps.provider    = p_provider
    AND wps.secret_name = p_secret_name;

  RETURN v_value;
END;
$$;

REVOKE ALL ON FUNCTION get_whatsapp_secret_value(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_whatsapp_secret_value(TEXT, TEXT) TO service_role;
