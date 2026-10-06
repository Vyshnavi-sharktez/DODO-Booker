-- ── fcm_vault_secrets ─────────────────────────────────────────────────────────
-- Tracks vault_secret_id references for admin-managed FCM secrets.
-- Mirrors the payment_gateway_secrets table pattern used by Razorpay.
-- No client SELECT/INSERT/UPDATE — all access is via SECURITY DEFINER functions.
--
-- Managed secrets:
--   push_function_secret    — Bearer token the DB trigger sends to the edge function
--   fcm_service_account_b64 — Firebase service account JSON (base64-encoded)

CREATE TABLE fcm_vault_secrets (
  secret_name     TEXT        PRIMARY KEY,
  vault_secret_id UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE fcm_vault_secrets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE fcm_vault_secrets FROM anon, authenticated;

-- ── upsert_fcm_vault_secret ───────────────────────────────────────────────────
-- Admin-only write. Stores the value in Vault and keeps only the UUID in our
-- table. Never returns the value. Mirrors upsert_gateway_secret exactly.
--
-- Orphan-safe: if vault.create_secret previously created an entry but returned
-- NULL (known pgsodium bug), the existing vault entry is detected and reused.

CREATE OR REPLACE FUNCTION upsert_fcm_vault_secret(
  p_name  TEXT,
  p_value TEXT
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
BEGIN
  IF p_name NOT IN ('push_function_secret', 'fcm_service_account_b64') THEN
    RAISE EXCEPTION 'invalid FCM secret name: %', p_name;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE auth_user_id = auth.uid() AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'admin authorisation required';
  END IF;

  IF p_value IS NULL OR length(trim(p_value)) = 0 THEN
    RAISE EXCEPTION 'secret value must not be empty';
  END IF;

  -- Step 1: check our tracking table for a linked vault entry.
  SELECT vault_secret_id INTO v_existing_vault_id
  FROM fcm_vault_secrets
  WHERE secret_name = p_name;

  IF v_existing_vault_id IS NOT NULL THEN
    PERFORM vault.update_secret(v_existing_vault_id, p_value);
    UPDATE fcm_vault_secrets SET updated_at = NOW() WHERE secret_name = p_name;
    RETURN;
  END IF;

  -- Step 2: detect orphaned vault entry (vault has entry by name but table has no UUID).
  -- Covers: vault entry was created directly via Supabase CLI / dashboard before this
  -- migration, OR a prior create_secret call succeeded in vault but returned NULL.
  SELECT id INTO v_orphan_vault_id
  FROM vault.secrets
  WHERE name = p_name;

  IF v_orphan_vault_id IS NOT NULL THEN
    PERFORM vault.update_secret(v_orphan_vault_id, p_value);
    INSERT INTO fcm_vault_secrets (secret_name, vault_secret_id)
    VALUES (p_name, v_orphan_vault_id)
    ON CONFLICT (secret_name) DO UPDATE SET
      vault_secret_id = EXCLUDED.vault_secret_id,
      updated_at      = NOW();
    RETURN;
  END IF;

  -- Step 3: no vault entry exists — create fresh.
  SELECT vault.create_secret(p_value, p_name) INTO v_new_vault_id;

  IF v_new_vault_id IS NULL THEN
    RAISE EXCEPTION
      'vault.create_secret returned NULL for "%". '
      'Ensure the supabase_vault extension is enabled and pgsodium is initialised.',
      p_name;
  END IF;

  INSERT INTO fcm_vault_secrets (secret_name, vault_secret_id)
  VALUES (p_name, v_new_vault_id)
  ON CONFLICT (secret_name) DO UPDATE SET
    vault_secret_id = EXCLUDED.vault_secret_id,
    updated_at      = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_fcm_vault_secret(TEXT, TEXT) TO authenticated;

-- ── fcm_vault_secret_is_set ───────────────────────────────────────────────────
-- Returns true if the named secret has been stored. Never returns the value.
-- For push_function_secret: also checks vault directly by name so secrets set
-- before this migration (via CLI / dashboard) are correctly detected.

CREATE OR REPLACE FUNCTION fcm_vault_secret_is_set(p_name TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
BEGIN
  -- Table-tracked entry (set via upsert_fcm_vault_secret).
  IF EXISTS (
    SELECT 1 FROM fcm_vault_secrets WHERE secret_name = p_name AND vault_secret_id IS NOT NULL
  ) THEN
    RETURN TRUE;
  END IF;

  -- Fallback: vault entry set before this migration or directly via CLI/dashboard.
  RETURN EXISTS (
    SELECT 1 FROM vault.decrypted_secrets
    WHERE name              = p_name
      AND decrypted_secret IS NOT NULL
      AND length(trim(decrypted_secret)) > 0
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fcm_vault_secret_is_set(TEXT) TO authenticated;

-- ── get_fcm_vault_secret_value ────────────────────────────────────────────────
-- Service-role-only. Called by the send-push-notification Edge Function.
-- Returns the decrypted secret value; refuses any JWT role other than service_role.
-- Two independent access layers (GRANT + auth.role() check inside function body).

CREATE OR REPLACE FUNCTION get_fcm_vault_secret_value(p_name TEXT)
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

  -- Prefer table-tracked entry (set via admin panel).
  SELECT ds.decrypted_secret INTO v_value
  FROM fcm_vault_secrets fvs
  JOIN vault.decrypted_secrets ds ON ds.id = fvs.vault_secret_id
  WHERE fvs.secret_name = p_name;

  -- Fallback to direct vault name lookup (legacy / CLI-set secrets).
  IF v_value IS NULL THEN
    SELECT decrypted_secret INTO v_value
    FROM vault.decrypted_secrets
    WHERE name = p_name;
  END IF;

  RETURN v_value;
END;
$$;

REVOKE ALL ON FUNCTION get_fcm_vault_secret_value(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_fcm_vault_secret_value(TEXT) TO service_role;
