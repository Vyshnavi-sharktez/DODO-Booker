-- Gemini Bot Configuration
-- bot_configs : non-secret settings (enabled, model, system_prompt, etc.)
-- bot_secrets : Gemini API key stored in Supabase Vault
-- RPCs        : upsert_bot_secret, bot_secret_is_set, get_bot_config
-- Seed        : DODO Bot admin_users row + default bot_configs row

-- ── bot_configs ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS bot_configs (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled       BOOLEAN     NOT NULL DEFAULT false,
  model            TEXT        NOT NULL DEFAULT 'gemini-1.5-flash',
  system_prompt    TEXT        NOT NULL DEFAULT '',
  max_history      INT         NOT NULL DEFAULT 10,
  handoff_triggers TEXT        NOT NULL DEFAULT 'agent,human,talk to person,real person,speak to someone',
  webhook_url      TEXT        NOT NULL DEFAULT '',
  bot_admin_id     UUID,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION fn_bot_configs_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bot_configs_updated_at ON bot_configs;
CREATE TRIGGER trg_bot_configs_updated_at
  BEFORE UPDATE ON bot_configs
  FOR EACH ROW EXECUTE FUNCTION fn_bot_configs_updated_at();

ALTER TABLE bot_configs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bot_configs_authenticated_all" ON bot_configs;
CREATE POLICY "bot_configs_authenticated_all"
  ON bot_configs FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "bot_configs_service_role_all" ON bot_configs;
CREATE POLICY "bot_configs_service_role_all"
  ON bot_configs FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

-- ── bot_secrets ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS bot_secrets (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  secret_name     TEXT        NOT NULL UNIQUE,
  vault_secret_id UUID,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION fn_bot_secrets_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bot_secrets_updated_at ON bot_secrets;
CREATE TRIGGER trg_bot_secrets_updated_at
  BEFORE UPDATE ON bot_secrets
  FOR EACH ROW EXECUTE FUNCTION fn_bot_secrets_updated_at();

ALTER TABLE bot_secrets ENABLE ROW LEVEL SECURITY;
-- No SELECT policy for authenticated — browser cannot read secret values.

DROP POLICY IF EXISTS "bot_secrets_service_role_all" ON bot_secrets;
CREATE POLICY "bot_secrets_service_role_all"
  ON bot_secrets FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

-- ── RPCs ──────────────────────────────────────────────────────────────────────

-- upsert_bot_secret: admin panel calls this to save Gemini API key into Vault.
-- Runs SECURITY DEFINER; value is never returned.
CREATE OR REPLACE FUNCTION upsert_bot_secret(
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
  v_vault_name        TEXT := 'bot:' || p_secret_name;
BEGIN
  SELECT vault_secret_id INTO v_existing_vault_id
  FROM bot_secrets WHERE secret_name = p_secret_name;

  IF v_existing_vault_id IS NOT NULL THEN
    PERFORM vault.update_secret(v_existing_vault_id, p_value);
    UPDATE bot_secrets SET updated_at = now() WHERE secret_name = p_secret_name;
  ELSE
    v_new_vault_id := vault.create_secret(p_value, v_vault_name);
    INSERT INTO bot_secrets (secret_name, vault_secret_id)
    VALUES (p_secret_name, v_new_vault_id)
    ON CONFLICT (secret_name) DO UPDATE
      SET vault_secret_id = EXCLUDED.vault_secret_id,
          updated_at      = now();
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_bot_secret(TEXT, TEXT) TO authenticated;

-- bot_secret_is_set: returns true if Vault secret exists for this name.
-- Lets admin UI show "Configured / Not set" without reading the value.
CREATE OR REPLACE FUNCTION bot_secret_is_set(p_secret_name TEXT)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM bot_secrets
    WHERE secret_name = p_secret_name AND vault_secret_id IS NOT NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION bot_secret_is_set(TEXT) TO authenticated;

-- get_bot_config: returns all config + decrypted API key.
-- Called ONLY by the Flask bot using the service_role JWT.
-- Two independent access-control layers:
--   Layer 1 (PostgreSQL): EXECUTE revoked from PUBLIC, granted only to service_role.
--   Layer 2 (Supabase JWT): auth.role() check inside the function body.
CREATE OR REPLACE FUNCTION get_bot_config()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_config  bot_configs%ROWTYPE;
  v_api_key TEXT;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Access denied: insufficient privileges';
  END IF;

  SELECT * INTO v_config FROM bot_configs LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT ds.decrypted_secret INTO v_api_key
  FROM bot_secrets bs
  JOIN vault.decrypted_secrets ds ON ds.id = bs.vault_secret_id
  WHERE bs.secret_name = 'gemini_api_key';

  RETURN jsonb_build_object(
    'is_enabled',        v_config.is_enabled,
    'model',             v_config.model,
    'system_prompt',     v_config.system_prompt,
    'max_history',       v_config.max_history,
    'handoff_triggers',  v_config.handoff_triggers,
    'bot_admin_id',      v_config.bot_admin_id,
    'api_key',           v_api_key
  );
END;
$$;

REVOKE ALL ON FUNCTION get_bot_config() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_bot_config() TO service_role;

-- ── Seed ──────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_bot_admin_id UUID := 'a0000000-b070-0000-0000-000000000000'::UUID;
BEGIN
  -- Bot admin user: no real auth account; bot inserts messages via service_role.
  -- Fixed ID ensures this seed is idempotent.
  INSERT INTO admin_users (id, auth_user_id, full_name, email, is_active, is_super_admin)
  VALUES (
    v_bot_admin_id,
    'a0000000-b070-0000-0000-000000000001'::UUID,
    'DODO Bot',
    'bot@dodo.internal',
    true,
    false
  )
  ON CONFLICT (id) DO NOTHING;

  -- Default bot_configs row (disabled; admin must enable after adding API key).
  INSERT INTO bot_configs (
    is_enabled,
    model,
    system_prompt,
    max_history,
    handoff_triggers,
    bot_admin_id
  )
  SELECT
    false,
    'gemini-1.5-flash',
    'You are DODO''s friendly customer support assistant. DODO is a home services platform in India offering cleaning, plumbing, AC repair, and more. Help customers with booking queries, cancellations, rescheduling, and general questions. Keep replies short and friendly. If you cannot resolve something, say "Let me connect you with our support team."',
    10,
    'agent,human,talk to person,real person,speak to someone',
    v_bot_admin_id
  WHERE NOT EXISTS (SELECT 1 FROM bot_configs);
END;
$$;
