-- Migration: 20261029000003_fix_upsert_call_secret.sql
-- Fix: upsert_call_secret used `SELECT id FROM vault.create_secret(...)` which
-- treats the function as a table-returning function and looks for a column named
-- "id".  vault.create_secret returns a UUID scalar; the correct form is
-- `SELECT vault.create_secret(...) INTO variable`.

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
    -- vault.create_secret returns a UUID scalar; use SELECT func() INTO, not
    -- SELECT col FROM func() which expects a table-returning function.
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
