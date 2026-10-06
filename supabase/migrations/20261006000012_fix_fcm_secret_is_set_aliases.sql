-- ── fcm_vault_secret_is_set (updated) ────────────────────────────────────────
-- Extends the original check to also match known alternate vault secret names.
-- This handles the case where secrets were stored in vault via Supabase CLI or
-- the Supabase dashboard using the legacy uppercase env-var-style names before
-- the admin panel vault management was available:
--
--   fcm_service_account_b64  ↔  FCM_SERVICE_ACCOUNT_JSON_B64
--   push_function_secret     ↔  PUSH_FUNCTION_SECRET
--
-- The lookup priority remains:
--   1. fcm_vault_secrets table (set via admin panel upsert_fcm_vault_secret)
--   2. vault.decrypted_secrets by canonical lowercase name
--   3. vault.decrypted_secrets by alternate uppercase name

CREATE OR REPLACE FUNCTION fcm_vault_secret_is_set(p_name TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_alt_name TEXT;
BEGIN
  -- 1. Table-tracked entry (set via admin panel).
  IF EXISTS (
    SELECT 1 FROM fcm_vault_secrets
    WHERE secret_name = p_name AND vault_secret_id IS NOT NULL
  ) THEN
    RETURN TRUE;
  END IF;

  -- 2. Direct vault lookup by canonical name.
  IF EXISTS (
    SELECT 1 FROM vault.decrypted_secrets
    WHERE name              = p_name
      AND decrypted_secret IS NOT NULL
      AND length(trim(decrypted_secret)) > 0
  ) THEN
    RETURN TRUE;
  END IF;

  -- 3. Alternate name — legacy uppercase names stored before this migration.
  v_alt_name := CASE p_name
    WHEN 'fcm_service_account_b64' THEN 'FCM_SERVICE_ACCOUNT_JSON_B64'
    WHEN 'push_function_secret'    THEN 'PUSH_FUNCTION_SECRET'
    ELSE NULL
  END;

  IF v_alt_name IS NOT NULL THEN
    RETURN EXISTS (
      SELECT 1 FROM vault.decrypted_secrets
      WHERE name              = v_alt_name
        AND decrypted_secret IS NOT NULL
        AND length(trim(decrypted_secret)) > 0
    );
  END IF;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION fcm_vault_secret_is_set(TEXT) TO authenticated;
