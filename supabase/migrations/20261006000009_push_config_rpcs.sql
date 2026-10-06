-- ── push_secret_is_configured ────────────────────────────────────────────────
-- Returns true if the push_function_secret vault secret is present and non-empty.
-- Never exposes the secret value. Mirrors gateway_secret_is_set for payment config.

CREATE OR REPLACE FUNCTION push_secret_is_configured()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM vault.decrypted_secrets
    WHERE name = 'push_function_secret'
      AND decrypted_secret IS NOT NULL
      AND length(trim(decrypted_secret)) > 0
  );
$$;

GRANT EXECUTE ON FUNCTION push_secret_is_configured() TO authenticated;

-- ── get_device_token_counts ───────────────────────────────────────────────────
-- Returns active/total device registration counts grouped by user_type + platform.
-- device_tokens has REVOKE ALL for authenticated users; this SECURITY DEFINER
-- function provides a safe read-only aggregate view for the admin status page.

CREATE OR REPLACE FUNCTION get_device_token_counts()
RETURNS TABLE (
  user_type    TEXT,
  platform     TEXT,
  active_count BIGINT,
  total_count  BIGINT
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    user_type,
    platform,
    COUNT(*) FILTER (WHERE is_active = TRUE) AS active_count,
    COUNT(*)                                  AS total_count
  FROM device_tokens
  GROUP BY user_type, platform
  ORDER BY user_type, platform;
$$;

GRANT EXECUTE ON FUNCTION get_device_token_counts() TO authenticated;
