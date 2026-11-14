-- Patch get_bot_config to return close_triggers (omitted in original RPC).
-- Without this, cfg.close_triggers is undefined in the edge function so
-- isClose is always false and conversations never auto-close.

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
    'close_triggers',    v_config.close_triggers,
    'bot_admin_id',      v_config.bot_admin_id,
    'api_key',           v_api_key
  );
END;
$$;

REVOKE ALL ON FUNCTION get_bot_config() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_bot_config() TO service_role;
