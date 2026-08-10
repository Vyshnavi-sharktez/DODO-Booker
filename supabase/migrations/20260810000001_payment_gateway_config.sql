-- Payment Gateway Configuration
-- Two tables:
--   payment_gateway_configs  — non-secret config (enabled, mode, public key)
--   payment_gateway_secrets  — secrets (key_secret, webhook_secret)
--
-- RLS design:
--   payment_gateway_configs: authenticated read/write, no anon access
--   payment_gateway_secrets: admin write-only via SECURITY DEFINER RPCs,
--                            service_role reads (edge functions bypass RLS)

-- ── payment_gateway_configs ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS payment_gateway_configs (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  gateway       TEXT        NOT NULL UNIQUE,
  is_enabled    BOOLEAN     NOT NULL DEFAULT false,
  mode          TEXT        NOT NULL DEFAULT 'test'
                            CHECK (mode IN ('test', 'live')),
  display_name  TEXT        NOT NULL DEFAULT '',
  public_key    TEXT        NOT NULL DEFAULT '',
  extra_config  JSONB       NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION fn_payment_gateway_configs_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_gateway_configs_updated_at ON payment_gateway_configs;
CREATE TRIGGER trg_payment_gateway_configs_updated_at
  BEFORE UPDATE ON payment_gateway_configs
  FOR EACH ROW EXECUTE FUNCTION fn_payment_gateway_configs_updated_at();

ALTER TABLE payment_gateway_configs ENABLE ROW LEVEL SECURITY;

-- Authenticated (admin panel): full read/write
DROP POLICY IF EXISTS "pgc_authenticated_all" ON payment_gateway_configs;
CREATE POLICY "pgc_authenticated_all"
  ON payment_gateway_configs FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

-- anon: no policy → denied

-- Seed Razorpay row (disabled by default)
INSERT INTO payment_gateway_configs (gateway, display_name)
VALUES ('razorpay', 'Pay with Razorpay')
ON CONFLICT (gateway) DO NOTHING;

-- ── payment_gateway_secrets ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS payment_gateway_secrets (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  gateway      TEXT        NOT NULL,
  secret_name  TEXT        NOT NULL,
  secret_value TEXT        NOT NULL DEFAULT '',
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (gateway, secret_name)
);

CREATE OR REPLACE FUNCTION fn_payment_gateway_secrets_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_gateway_secrets_updated_at ON payment_gateway_secrets;
CREATE TRIGGER trg_payment_gateway_secrets_updated_at
  BEFORE UPDATE ON payment_gateway_secrets
  FOR EACH ROW EXECUTE FUNCTION fn_payment_gateway_secrets_updated_at();

ALTER TABLE payment_gateway_secrets ENABLE ROW LEVEL SECURITY;

-- No SELECT policy for authenticated → admin browser can never read secrets back.
-- service_role bypasses RLS → edge functions can SELECT.
-- No anon policy → denied.

-- ── SECURITY DEFINER RPCs ─────────────────────────────────────────────────────

-- upsert_gateway_secret: admin panel calls this to save a secret.
-- Runs as postgres (superuser), bypasses RLS. Returns void — value never echoed.
CREATE OR REPLACE FUNCTION upsert_gateway_secret(
  p_gateway     TEXT,
  p_secret_name TEXT,
  p_value       TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO payment_gateway_secrets (gateway, secret_name, secret_value)
  VALUES (p_gateway, p_secret_name, p_value)
  ON CONFLICT (gateway, secret_name)
  DO UPDATE SET
    secret_value = EXCLUDED.secret_value,
    updated_at   = now();
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_gateway_secret(TEXT, TEXT, TEXT) TO authenticated;

-- gateway_secret_is_set: returns true if a non-empty value exists.
-- Lets the admin UI show "Configured / Not set" without reading the value.
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
    WHERE gateway     = p_gateway
      AND secret_name = p_secret_name
      AND secret_value IS NOT NULL
      AND secret_value <> ''
  );
END;
$$;

GRANT EXECUTE ON FUNCTION gateway_secret_is_set(TEXT, TEXT) TO authenticated;
