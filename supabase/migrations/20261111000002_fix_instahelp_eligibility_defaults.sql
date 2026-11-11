-- Fix: allow_free_vendors COALESCE default was 'true' in both eligibility RPCs,
-- meaning the setting had no effect until explicitly saved to the DB.
-- Corrected to 'false' to match the Flutter default and enforce subscription by default.
-- Also seeds all instahelp_subscription_* keys so the COALESCE fallback is never reached.

-- ── 1. Seed missing settings with safe defaults ───────────────────────────────

INSERT INTO public.settings (setting_key, setting_value)
VALUES
  ('instahelp_subscription_enabled',            'false'),
  ('instahelp_subscription_require_active',      'false'),
  ('instahelp_subscription_allow_free_vendors',  'false'),
  ('instahelp_subscription_free_order_allowance','0'),
  ('instahelp_subscription_order_counting_method','completed'),
  ('instahelp_subscription_auto_restrict',       'true'),
  ('instahelp_subscription_grace_period_days',   '0'),
  ('instahelp_subscription_expiry_enforcement',  'true')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 2. Fix check_vendor_instahelp_eligibility ─────────────────────────────────

CREATE OR REPLACE FUNCTION check_vendor_instahelp_eligibility(p_vendor_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled         BOOLEAN;
  v_free_allowance  INT;
  v_require_active  BOOLEAN;
  v_allow_free      BOOLEAN;
  v_grace_days      INT;
  v_expiry_enforced BOOLEAN;
  v_cutoff          TIMESTAMPTZ;
  v_orders_used     INT;
  v_is_active       BOOLEAN;
BEGIN
  SELECT
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_enabled'            THEN setting_value END), 'false') = 'true',
    COALESCE(NULLIF(TRIM(COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_free_order_allowance' THEN setting_value END), '0')), ''), '0')::INT,
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_require_active'     THEN setting_value END), 'false') = 'true',
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_allow_free_vendors' THEN setting_value END), 'false') = 'true',
    COALESCE(NULLIF(TRIM(COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_grace_period_days'   THEN setting_value END), '0')), ''), '0')::INT,
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_expiry_enforcement' THEN setting_value END), 'true')  = 'true'
  INTO v_enabled, v_free_allowance, v_require_active, v_allow_free, v_grace_days, v_expiry_enforced
  FROM settings
  WHERE setting_key LIKE 'instahelp_subscription_%';

  IF NOT COALESCE(v_enabled, FALSE) THEN
    RETURN TRUE;
  END IF;

  SELECT is_active INTO v_is_active FROM vendors WHERE id = p_vendor_id;
  IF NOT FOUND OR NOT v_is_active THEN
    RETURN FALSE;
  END IF;

  IF COALESCE(v_free_allowance, 0) > 0 THEN
    SELECT COALESCE(orders_used, 0) INTO v_orders_used
      FROM vendor_instahelp_free_orders WHERE vendor_id = p_vendor_id;
    IF COALESCE(v_orders_used, 0) < v_free_allowance THEN
      RETURN TRUE;
    END IF;
  END IF;

  IF NOT COALESCE(v_require_active, FALSE) THEN
    RETURN COALESCE(v_allow_free, FALSE);
  END IF;

  IF COALESCE(v_expiry_enforced, TRUE) THEN
    v_cutoff := NOW() - (COALESCE(v_grace_days, 0) || ' days')::INTERVAL;
  ELSE
    v_cutoff := '-infinity'::TIMESTAMPTZ;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM vendor_subscriptions vs
    JOIN subscription_plans sp ON sp.id = vs.plan_id
    WHERE vs.vendor_id = p_vendor_id
      AND vs.catalog_node_id IS NULL
      AND vs.status = 'active'
      AND vs.expiry_date > v_cutoff
      AND (sp.permissions->>'allow_instahelp')::BOOLEAN = TRUE
  ) THEN
    RETURN TRUE;
  END IF;

  RETURN COALESCE(v_allow_free, FALSE);
END;
$$;

-- ── 3. Fix get_instahelp_eligible_vendor_ids ──────────────────────────────────

CREATE OR REPLACE FUNCTION get_instahelp_eligible_vendor_ids()
RETURNS SETOF UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled         BOOLEAN;
  v_free_allowance  INT;
  v_require_active  BOOLEAN;
  v_allow_free      BOOLEAN;
  v_grace_days      INT;
  v_expiry_enforced BOOLEAN;
  v_cutoff          TIMESTAMPTZ;
BEGIN
  SELECT
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_enabled'            THEN setting_value END), 'false') = 'true',
    COALESCE(NULLIF(TRIM(COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_free_order_allowance' THEN setting_value END), '0')), ''), '0')::INT,
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_require_active'     THEN setting_value END), 'false') = 'true',
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_allow_free_vendors' THEN setting_value END), 'false') = 'true',
    COALESCE(NULLIF(TRIM(COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_grace_period_days'   THEN setting_value END), '0')), ''), '0')::INT,
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_expiry_enforcement' THEN setting_value END), 'true')  = 'true'
  INTO v_enabled, v_free_allowance, v_require_active, v_allow_free, v_grace_days, v_expiry_enforced
  FROM settings
  WHERE setting_key LIKE 'instahelp_subscription_%';

  IF NOT COALESCE(v_enabled, FALSE) THEN
    RETURN QUERY SELECT id FROM vendors WHERE is_active = TRUE;
    RETURN;
  END IF;

  IF NOT COALESCE(v_require_active, FALSE) AND COALESCE(v_allow_free, FALSE) THEN
    RETURN QUERY SELECT id FROM vendors WHERE is_active = TRUE;
    RETURN;
  END IF;

  IF COALESCE(v_expiry_enforced, TRUE) THEN
    v_cutoff := NOW() - (COALESCE(v_grace_days, 0) || ' days')::INTERVAL;
  ELSE
    v_cutoff := '-infinity'::TIMESTAMPTZ;
  END IF;

  RETURN QUERY
    SELECT DISTINCT vr.id
    FROM vendors vr
    WHERE vr.is_active = TRUE
      AND (
        (
          COALESCE(v_free_allowance, 0) > 0
          AND COALESCE(
            (SELECT ifo.orders_used FROM vendor_instahelp_free_orders ifo
             WHERE ifo.vendor_id = vr.id),
            0
          ) < v_free_allowance
        )
        OR
        EXISTS (
          SELECT 1
          FROM vendor_subscriptions vs
          JOIN subscription_plans sp ON sp.id = vs.plan_id
          WHERE vs.vendor_id = vr.id
            AND vs.catalog_node_id IS NULL
            AND vs.status = 'active'
            AND vs.expiry_date > v_cutoff
            AND (sp.permissions->>'allow_instahelp')::BOOLEAN = TRUE
        )
        OR
        (
          COALESCE(v_allow_free, FALSE)
          AND NOT EXISTS (
            SELECT 1 FROM vendor_subscriptions vs2
            WHERE vs2.vendor_id = vr.id
              AND vs2.catalog_node_id IS NULL
              AND vs2.status = 'active'
              AND vs2.expiry_date > v_cutoff
          )
        )
      );
END;
$$;
