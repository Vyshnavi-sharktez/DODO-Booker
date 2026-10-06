-- ── get_push_test_targets ─────────────────────────────────────────────────────
-- Returns distinct active device-token users for the given user_type.
-- Called by the admin FCM test panel to populate the device-picker dropdown.
-- Never exposes token strings — only user_id, a safe display name, device count,
-- and platform list.
-- Caller must be an active admin (auth.uid() must match an admin_users row).

CREATE OR REPLACE FUNCTION get_push_test_targets(p_user_type TEXT)
RETURNS TABLE (
  user_id             UUID,
  display_name        TEXT,
  active_device_count INT,
  platforms           TEXT[]
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authenticated session required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE auth_user_id = auth.uid() AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'admin access required';
  END IF;

  IF p_user_type NOT IN ('customer', 'vendor', 'admin') THEN
    RAISE EXCEPTION 'invalid user_type';
  END IF;

  IF p_user_type = 'customer' THEN
    RETURN QUERY
      SELECT
        dt.user_id,
        COALESCE(NULLIF(TRIM(c.full_name), ''), c.phone) AS display_name,
        COUNT(dt.id)::INT                                 AS active_device_count,
        ARRAY_AGG(DISTINCT dt.platform ORDER BY dt.platform) AS platforms
      FROM device_tokens dt
      LEFT JOIN customers c ON c.id = dt.user_id
      WHERE dt.user_type = 'customer' AND dt.is_active = TRUE
      GROUP BY dt.user_id, c.full_name, c.phone
      ORDER BY display_name;

  ELSIF p_user_type = 'vendor' THEN
    RETURN QUERY
      SELECT
        dt.user_id,
        COALESCE(NULLIF(TRIM(v.business_name), ''), v.phone) AS display_name,
        COUNT(dt.id)::INT                                      AS active_device_count,
        ARRAY_AGG(DISTINCT dt.platform ORDER BY dt.platform)  AS platforms
      FROM device_tokens dt
      LEFT JOIN vendors v ON v.id = dt.user_id
      WHERE dt.user_type = 'vendor' AND dt.is_active = TRUE
      GROUP BY dt.user_id, v.business_name, v.phone
      ORDER BY display_name;

  ELSE -- admin
    RETURN QUERY
      SELECT
        dt.user_id,
        COALESCE(NULLIF(TRIM(au.full_name), ''), au.email) AS display_name,
        COUNT(dt.id)::INT                                   AS active_device_count,
        ARRAY_AGG(DISTINCT dt.platform ORDER BY dt.platform) AS platforms
      FROM device_tokens dt
      LEFT JOIN admin_users au ON au.id = dt.user_id
      WHERE dt.user_type = 'admin' AND dt.is_active = TRUE
      GROUP BY dt.user_id, au.full_name, au.email
      ORDER BY display_name;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION get_push_test_targets(TEXT) TO authenticated;


-- ── get_push_delivery_result ──────────────────────────────────────────────────
-- Returns the tokens_sent / tokens_failed counts for a single notification_id.
-- Used by the test panel to poll the delivery outcome after inserting a test
-- notification. Returns NULL (no row) if the Edge Function has not yet recorded
-- results — caller should treat that as "pending".
-- Requires an active admin session (same guard as above).

CREATE OR REPLACE FUNCTION get_push_delivery_result(p_notification_id UUID)
RETURNS TABLE (
  tokens_sent   INT,
  tokens_failed INT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authenticated session required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE auth_user_id = auth.uid() AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'admin access required';
  END IF;

  RETURN QUERY
    SELECT pd.tokens_sent, pd.tokens_failed
    FROM push_deliveries pd
    WHERE pd.notification_id = p_notification_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_push_delivery_result(UUID) TO authenticated;
