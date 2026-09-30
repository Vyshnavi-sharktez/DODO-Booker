-- Fix: upsert_gateway_secret fails with duplicate key on secrets_name_idx.
--
-- Root cause:
--   Migration 20260810000002 called vault.create_secret() and stored its
--   return value via := (PL/pgSQL assignment).  In some environments that
--   call succeeded inside Vault (the entry was created) but returned NULL
--   back to the caller.  The INSERT therefore stored vault_secret_id = NULL.
--
--   Migration 20260810000003 fixed the NULL guard for future rows, but did
--   not handle rows that were already stored with vault_secret_id = NULL
--   while an orphaned vault.secrets entry with the same canonical name
--   (e.g. "razorpay:key_secret") still exists.
--
--   On the next save attempt the function finds vault_secret_id IS NULL,
--   falls through to the ELSE branch, and tries vault.create_secret() with
--   the same name → duplicate key value violates unique constraint
--   "secrets_name_idx" on vault.secrets.
--
-- Fix:
--   In the ELSE branch, before creating a new Vault entry, query
--   vault.secrets by name.  If an orphaned entry exists, update it
--   in-place (re-encrypts with a new nonce) and link its id back into
--   payment_gateway_secrets.  Only if no Vault entry exists at all do we
--   call vault.create_secret().
--
-- No data is lost: the secret value is overwritten with the new value the
-- admin entered, which is exactly the intended behaviour when replacing
-- old credentials with new ones.
--
-- No unrelated secrets, gateway configs, or other tables are touched.

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
  v_orphan_vault_id   UUID;
  v_new_vault_id      UUID;
  v_vault_name        TEXT := p_gateway || ':' || p_secret_name;
BEGIN
  -- ── Step 1: check our table for a linked Vault entry ──────────────────────
  SELECT vault_secret_id INTO v_existing_vault_id
  FROM payment_gateway_secrets
  WHERE gateway = p_gateway AND secret_name = p_secret_name;

  IF v_existing_vault_id IS NOT NULL THEN
    -- Happy path: vault ID is known → update the encrypted value in-place.
    PERFORM vault.update_secret(v_existing_vault_id, p_value);
    UPDATE payment_gateway_secrets
    SET updated_at = now()
    WHERE gateway = p_gateway AND secret_name = p_secret_name;
    RETURN;
  END IF;

  -- ── Step 2: detect orphaned Vault entry (vault_secret_id was NULL) ────────
  -- Happens when a prior vault.create_secret() call created the Vault entry
  -- but returned NULL, so our row stored vault_secret_id = NULL.
  SELECT id INTO v_orphan_vault_id
  FROM vault.secrets
  WHERE name = v_vault_name;

  IF v_orphan_vault_id IS NOT NULL THEN
    -- Orphaned Vault entry found: update its encrypted value and re-link.
    PERFORM vault.update_secret(v_orphan_vault_id, p_value);
    INSERT INTO payment_gateway_secrets (gateway, secret_name, vault_secret_id)
    VALUES (p_gateway, p_secret_name, v_orphan_vault_id)
    ON CONFLICT (gateway, secret_name)
    DO UPDATE SET
      vault_secret_id = EXCLUDED.vault_secret_id,
      updated_at      = now();
    RETURN;
  END IF;

  -- ── Step 3: no Vault entry exists at all — create fresh ───────────────────
  SELECT vault.create_secret(p_value, v_vault_name) INTO v_new_vault_id;

  IF v_new_vault_id IS NULL THEN
    RAISE EXCEPTION
      'vault.create_secret returned NULL for "%". '
      'Ensure the supabase_vault extension is enabled and pgsodium is '
      'initialised on this project.',
      v_vault_name;
  END IF;

  INSERT INTO payment_gateway_secrets (gateway, secret_name, vault_secret_id)
  VALUES (p_gateway, p_secret_name, v_new_vault_id)
  ON CONFLICT (gateway, secret_name)
  DO UPDATE SET
    vault_secret_id = EXCLUDED.vault_secret_id,
    updated_at      = now();
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_gateway_secret(TEXT, TEXT, TEXT) TO authenticated;
