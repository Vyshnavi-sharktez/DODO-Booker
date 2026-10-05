-- Fix admin identity check in register_device_token and deactivate_device_token.
-- Both RPCs incorrectly referenced admin_users.user_id which does not exist.
-- The correct column is admin_users.auth_user_id (same pattern used throughout the project).

CREATE OR REPLACE FUNCTION register_device_token(
  p_user_type TEXT,
  p_user_id   UUID,
  p_platform  TEXT,
  p_token     TEXT,
  p_phone     TEXT DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF p_user_type NOT IN ('customer', 'vendor', 'admin') THEN
    RAISE EXCEPTION 'invalid user_type provided';
  END IF;
  IF p_platform NOT IN ('android', 'ios', 'web') THEN
    RAISE EXCEPTION 'invalid platform provided';
  END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RAISE EXCEPTION 'token must not be empty';
  END IF;

  IF p_user_type = 'customer' THEN
    IF p_phone IS NULL THEN
      RAISE EXCEPTION 'phone required for customer token registration';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM customers
      WHERE id = p_user_id AND phone = p_phone AND is_active = TRUE
    ) THEN
      RAISE EXCEPTION 'identity validation failed';
    END IF;

  ELSIF p_user_type = 'vendor' THEN
    IF p_phone IS NULL THEN
      RAISE EXCEPTION 'phone required for vendor token registration';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM vendors WHERE id = p_user_id AND phone = p_phone AND is_active = TRUE
    ) THEN
      RAISE EXCEPTION 'identity validation failed';
    END IF;

  ELSIF p_user_type = 'admin' THEN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'authenticated session required';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM admin_users
      WHERE id = p_user_id AND auth_user_id = auth.uid() AND is_active = TRUE
    ) THEN
      RAISE EXCEPTION 'identity validation failed';
    END IF;
  END IF;

  INSERT INTO device_tokens (user_type, user_id, platform, token, is_active, updated_at)
  VALUES (p_user_type, p_user_id, p_platform, p_token, TRUE, NOW())
  ON CONFLICT (user_type, user_id, platform, token)
  DO UPDATE SET is_active = TRUE, updated_at = NOW();

EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN (
      'identity validation failed',
      'phone required for customer token registration',
      'phone required for vendor token registration',
      'authenticated session required',
      'invalid user_type provided',
      'invalid platform provided',
      'token must not be empty'
    ) THEN
      RAISE;
    END IF;
    RAISE LOG 'register_device_token unexpected error for user_type=%, SQLSTATE=%',
      p_user_type, SQLSTATE;
    RAISE EXCEPTION 'token registration failed';
END;
$$;

CREATE OR REPLACE FUNCTION deactivate_device_token(
  p_user_type TEXT,
  p_user_id   UUID,
  p_token     TEXT,
  p_phone     TEXT DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF p_user_type NOT IN ('customer', 'vendor', 'admin') THEN
    RAISE EXCEPTION 'invalid user_type provided';
  END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RAISE EXCEPTION 'token must not be empty';
  END IF;

  IF p_user_type = 'customer' THEN
    IF p_phone IS NULL THEN
      RAISE EXCEPTION 'phone required for customer token deactivation';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM customers WHERE id = p_user_id AND phone = p_phone
    ) THEN
      RAISE EXCEPTION 'identity validation failed';
    END IF;

  ELSIF p_user_type = 'vendor' THEN
    IF p_phone IS NULL THEN
      RAISE EXCEPTION 'phone required for vendor token deactivation';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM vendors WHERE id = p_user_id AND phone = p_phone
    ) THEN
      RAISE EXCEPTION 'identity validation failed';
    END IF;

  ELSIF p_user_type = 'admin' THEN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'authenticated session required';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM admin_users WHERE id = p_user_id AND auth_user_id = auth.uid()
    ) THEN
      RAISE EXCEPTION 'identity validation failed';
    END IF;
  END IF;

  UPDATE device_tokens
  SET is_active = FALSE, updated_at = NOW()
  WHERE user_type = p_user_type AND user_id = p_user_id AND token = p_token;

EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN (
      'identity validation failed',
      'phone required for customer token deactivation',
      'phone required for vendor token deactivation',
      'authenticated session required',
      'invalid user_type provided',
      'token must not be empty'
    ) THEN
      RAISE;
    END IF;
    RAISE LOG 'deactivate_device_token unexpected error for user_type=%, SQLSTATE=%',
      p_user_type, SQLSTATE;
    RAISE EXCEPTION 'token deactivation failed';
END;
$$;
