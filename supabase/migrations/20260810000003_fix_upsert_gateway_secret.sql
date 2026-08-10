-- Fix: upsert_gateway_secret silently stored NULL vault_secret_id.
--
-- Root cause: vault.create_secret() can return NULL in some Supabase
-- environments (extension not fully initialised, key rotation in progress,
-- etc.).  The previous function assigned the return value without checking,
-- so the INSERT stored vault_secret_id = NULL.  gateway_secret_is_set() then
-- correctly evaluated vault_secret_id IS NOT NULL → false, showing "Not set"
-- even after a successful-looking save.
--
-- Fix: raise an explicit exception if vault.create_secret returns NULL so the
-- failure surfaces as an error in the Admin Panel instead of silent data loss.
-- Also switched the assignment to SELECT ... INTO, which is the idiomatic
-- PL/pgSQL form for capturing a scalar function return and is more reliable
-- across PostgREST / pgsodium version combinations.

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
    -- Create a new Vault secret.
    -- Use SELECT INTO (idiomatic PL/pgSQL scalar capture) instead of :=
    SELECT vault.create_secret(p_value, v_vault_name) INTO v_new_vault_id;

    -- Guard: raise a clear error rather than silently storing NULL.
    -- This surfaces vault misconfiguration as a visible Admin Panel error
    -- instead of an invisible "Not set" after refresh.
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
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_gateway_secret(TEXT, TEXT, TEXT) TO authenticated;
