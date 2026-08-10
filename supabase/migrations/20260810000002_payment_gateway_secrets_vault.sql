-- Migrate payment_gateway_secrets to Supabase Vault encrypted storage.
--
-- Problem with migration 20260810000001:
--   secret_value TEXT stored secrets as plaintext in the database.
--   RLS blocked API reads, but the values were visible in pg_dump, psql,
--   Supabase Studio (postgres role), and any future query-log exposure.
--
-- This migration:
--   1. Drops the plaintext secret_value column (table is empty — this is a
--      fresh feature with no real credentials stored yet).
--   2. Adds vault_secret_id UUID to point into Supabase Vault.
--   3. Replaces upsert_gateway_secret to call vault.create_secret /
--      vault.update_secret so values are encrypted at rest by pgsodium
--      (XSalsa20-Poly1305). The pgsodium root key lives outside the
--      PostgreSQL data directory — a full pg_dump cannot decrypt secrets.
--   4. Replaces gateway_secret_is_set to check vault_secret_id IS NOT NULL.
--   5. Adds get_gateway_secret_value, callable only by service_role, which
--      joins to vault.decrypted_secrets and returns the decrypted value.
--      Edge functions call this RPC with the service_role JWT.
--
-- Requires: supabase_vault extension (enabled by default in Supabase projects).

-- ── Alter payment_gateway_secrets ─────────────────────────────────────────────

-- Drop the plaintext column. Safe: table is empty (no seed data in migration 1).
ALTER TABLE payment_gateway_secrets
  DROP COLUMN IF EXISTS secret_value;

-- Add vault reference column.
ALTER TABLE payment_gateway_secrets
  ADD COLUMN IF NOT EXISTS vault_secret_id UUID;

-- ── Replace upsert_gateway_secret ─────────────────────────────────────────────
-- Now stores the value in Vault and keeps only the UUID in our table.
-- Returns void — the plaintext value is never returned to the caller.

CREATE OR REPLACE FUNCTION upsert_gateway_secret(
  p_gateway     TEXT,
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
  v_vault_name        TEXT := p_gateway || ':' || p_secret_name;
BEGIN
  -- Look up whether we already have a Vault entry for this secret.
  SELECT vault_secret_id INTO v_existing_vault_id
  FROM payment_gateway_secrets
  WHERE gateway = p_gateway AND secret_name = p_secret_name;

  IF v_existing_vault_id IS NOT NULL THEN
    -- Update the existing Vault secret in-place (re-encrypts with a new nonce).
    PERFORM vault.update_secret(v_existing_vault_id, p_value);
    UPDATE payment_gateway_secrets
    SET updated_at = now()
    WHERE gateway = p_gateway AND secret_name = p_secret_name;
  ELSE
    -- Create a new Vault secret; store the returned UUID.
    v_new_vault_id := vault.create_secret(p_value, v_vault_name);
    INSERT INTO payment_gateway_secrets (gateway, secret_name, vault_secret_id)
    VALUES (p_gateway, p_secret_name, v_new_vault_id)
    ON CONFLICT (gateway, secret_name)
    DO UPDATE SET
      vault_secret_id = EXCLUDED.vault_secret_id,
      updated_at      = now();
  END IF;
END;
$$;

-- Grant remains the same: admin panel (authenticated) can call this to write.
GRANT EXECUTE ON FUNCTION upsert_gateway_secret(TEXT, TEXT, TEXT) TO authenticated;

-- ── Replace gateway_secret_is_set ────────────────────────────────────────────
-- Checks the Vault reference column — no secret value is ever returned.

CREATE OR REPLACE FUNCTION gateway_secret_is_set(
  p_gateway     TEXT,
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
    FROM payment_gateway_secrets
    WHERE gateway        = p_gateway
      AND secret_name    = p_secret_name
      AND vault_secret_id IS NOT NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION gateway_secret_is_set(TEXT, TEXT) TO authenticated;

-- ── Add get_gateway_secret_value (service_role only) ─────────────────────────
-- Called exclusively by Edge Functions using the service_role JWT.
-- Joins to vault.decrypted_secrets (pgsodium decrypts in-process).
-- The decrypted value is returned only to the Edge Function's memory —
-- it is never written back to the DB and never appears in a client response.
--
-- Access control — two independent layers:
--   Layer 1 (PostgreSQL): EXECUTE revoked from PUBLIC, granted only to
--            service_role. anon and authenticated cannot call this function.
--   Layer 2 (Supabase JWT): auth.role() check inside the function body.
--            Even if the GRANT were accidentally widened, the function would
--            still refuse any caller whose JWT is not service_role.

CREATE OR REPLACE FUNCTION get_gateway_secret_value(
  p_gateway     TEXT,
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
  -- Defense-in-depth: refuse any JWT role other than service_role.
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Access denied: insufficient privileges';
  END IF;

  SELECT ds.decrypted_secret INTO v_value
  FROM payment_gateway_secrets pgs
  JOIN vault.decrypted_secrets ds ON ds.id = pgs.vault_secret_id
  WHERE pgs.gateway     = p_gateway
    AND pgs.secret_name = p_secret_name;

  RETURN v_value;
END;
$$;

-- Revoke from PUBLIC first (PostgreSQL grants EXECUTE to PUBLIC by default).
REVOKE ALL ON FUNCTION get_gateway_secret_value(TEXT, TEXT) FROM PUBLIC;
-- Grant only to service_role (Edge Functions).
GRANT EXECUTE ON FUNCTION get_gateway_secret_value(TEXT, TEXT) TO service_role;
