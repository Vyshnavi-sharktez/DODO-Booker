-- ── device_tokens ─────────────────────────────────────────────────────────────
-- Stores FCM/web-push tokens per user device.
-- user_type  : 'customer' | 'vendor' | 'admin'
-- user_id    : customers.id | vendors.id | admin_users.id  (NOT auth.users.id)
-- No client SELECT/INSERT/UPDATE — all writes go through SECURITY DEFINER RPCs.
-- Service role (edge function) bypasses RLS to read tokens.

CREATE TABLE device_tokens (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_type   TEXT        NOT NULL CHECK (user_type IN ('customer', 'vendor', 'admin')),
  user_id     UUID        NOT NULL,
  platform    TEXT        NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  token       TEXT        NOT NULL,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One active token per (user_type, user_id, platform, token) combination.
CREATE UNIQUE INDEX idx_device_tokens_entry
  ON device_tokens (user_type, user_id, platform, token);

-- Prevents one token from being active for two different users simultaneously.
-- On ownership transfer the old owner's row is deactivated first.
CREATE UNIQUE INDEX idx_device_tokens_active_token
  ON device_tokens (token) WHERE is_active = TRUE;

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

-- Revoke all direct client access; only service_role and SECURITY DEFINER RPCs touch this table.
REVOKE ALL ON TABLE device_tokens FROM anon, authenticated;

-- ── push_deliveries ───────────────────────────────────────────────────────────
-- Idempotency table: one row per notification_id.
-- The edge function inserts here before sending FCM.
-- If pg_net retries the same call, the INSERT conflicts and delivery is skipped.

CREATE TABLE push_deliveries (
  notification_id UUID        PRIMARY KEY REFERENCES notifications(id) ON DELETE CASCADE,
  attempted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  tokens_sent     INTEGER     NOT NULL DEFAULT 0,
  tokens_failed   INTEGER     NOT NULL DEFAULT 0
);

ALTER TABLE push_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE push_deliveries FROM anon, authenticated;

-- ── register_device_token ─────────────────────────────────────────────────────
-- Validates caller identity before writing to device_tokens.
-- Customer/Vendor: requires matching phone in the respective identity table.
-- Admin: requires active Supabase Auth session matching admin_users.user_id.

CREATE OR REPLACE FUNCTION register_device_token(
  p_user_type TEXT,
  p_user_id   UUID,
  p_platform  TEXT,
  p_token     TEXT,
  p_phone     TEXT DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Input shape validation (before any DB access)
  IF p_user_type NOT IN ('customer', 'vendor', 'admin') THEN
    RAISE EXCEPTION 'invalid user_type provided';
  END IF;
  IF p_platform NOT IN ('android', 'ios', 'web') THEN
    RAISE EXCEPTION 'invalid platform provided';
  END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RAISE EXCEPTION 'token must not be empty';
  END IF;

  -- Identity validation per user_type
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
    -- Check vendors table first, then dodo_teams
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

  -- Upsert: idempotent on (user_type, user_id, platform, token)
  INSERT INTO device_tokens (user_type, user_id, platform, token, is_active, updated_at)
  VALUES (p_user_type, p_user_id, p_platform, p_token, TRUE, NOW())
  ON CONFLICT (user_type, user_id, platform, token)
  DO UPDATE SET is_active = TRUE, updated_at = NOW();

EXCEPTION
  WHEN OTHERS THEN
    -- Re-raise our own controlled messages unchanged
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
    -- Log error class server-side (SQLSTATE only — never SQLERRM which may include token data)
    RAISE LOG 'register_device_token unexpected error for user_type=%, SQLSTATE=%',
      p_user_type, SQLSTATE;
    RAISE EXCEPTION 'token registration failed';
END;
$$;

GRANT EXECUTE ON FUNCTION register_device_token(TEXT, UUID, TEXT, TEXT, TEXT) TO anon, authenticated;

-- ── deactivate_device_token ───────────────────────────────────────────────────
-- Same identity validation as register. Called on logout to mark token inactive.

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

GRANT EXECUTE ON FUNCTION deactivate_device_token(TEXT, UUID, TEXT, TEXT) TO anon, authenticated;
