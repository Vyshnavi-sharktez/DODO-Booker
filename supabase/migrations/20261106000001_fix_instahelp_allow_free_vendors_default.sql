-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: instahelp_subscription_allow_free_vendors default
--
-- Problem: check_vendor_instahelp_eligibility() and get_instahelp_eligible_vendor_ids()
-- both fell back to COALESCE(v_allow_free, TRUE) when the setting was absent from
-- the DB.  Any vendor without a subscription could receive InstaHelp bookings
-- simply because the admin had never explicitly saved the setting.
--
-- Changes:
--   1. Seeds all instahelp_subscription_* settings (ON CONFLICT DO NOTHING —
--      explicitly saved admin values are preserved).
--   2. Replaces check_vendor_instahelp_eligibility() with corrected defaults.
--   3. Replaces get_instahelp_eligible_vendor_ids() with corrected defaults.
--
-- After this migration the COALESCE fallback for allow_free_vendors is FALSE,
-- so a missing setting never silently grants eligibility.
--
-- Eligibility matrix (enforcement on, allowance = 0):
--   Vendor state                                     | Eligible?
--   -------------------------------------------------|----------
--   No subscription, allow_free_vendors = false      | NO  ← was incorrectly YES
--   No subscription, allow_free_vendors = true       | YES (admin opted in)
--   Active subscription, allow_instahelp = true      | YES
--   Active subscription, allow_instahelp = false     | NO  (falls to allow_free check)
--   Expired subscription (past grace)                | NO  (falls to allow_free check)
--   Free orders remaining (allowance > 0, used < N)  | YES
--   Free orders exhausted                            | falls through to subscription
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Seed all InstaHelp subscription settings ───────────────────────────────
-- ON CONFLICT DO NOTHING preserves any value an admin has explicitly saved.
-- New installs and installs that never saved these keys get safe defaults.

INSERT INTO settings (setting_key, setting_value) VALUES
  ('instahelp_subscription_enabled',              'false'),
  ('instahelp_subscription_require_active',       'false'),
  ('instahelp_subscription_allow_free_vendors',   'false'),  -- was implicitly 'true'; now explicit 'false'
  ('instahelp_subscription_free_order_allowance', '0'),
  ('instahelp_subscription_order_counting_method','completed'),
  ('instahelp_subscription_auto_restrict',        'true'),
  ('instahelp_subscription_grace_period_days',    '0'),
  ('instahelp_subscription_expiry_enforcement',   'true')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 2. check_vendor_instahelp_eligibility — corrected defaults ────────────────
-- Changes from 20261105000014:
--   • COALESCE for allow_free_vendors setting read: 'true' → 'false'
--   • COALESCE(v_allow_free, TRUE) → COALESCE(v_allow_free, FALSE) (two sites)

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

  -- Module off → all vendors eligible
  IF NOT COALESCE(v_enabled, FALSE) THEN
    RETURN TRUE;
  END IF;

  -- Vendor must be active
  SELECT is_active INTO v_is_active FROM vendors WHERE id = p_vendor_id;
  IF NOT FOUND OR NOT v_is_active THEN
    RETURN FALSE;
  END IF;

  -- Free order allowance check (allowance = 0 means feature disabled)
  IF COALESCE(v_free_allowance, 0) > 0 THEN
    SELECT COALESCE(orders_used, 0) INTO v_orders_used
      FROM vendor_instahelp_free_orders WHERE vendor_id = p_vendor_id;
    IF COALESCE(v_orders_used, 0) < v_free_allowance THEN
      RETURN TRUE;
    END IF;
    -- Free orders exhausted — fall through to subscription check
  END IF;

  -- No active subscription required → eligible only if allow_free_vendors is on
  -- Default FALSE: missing config does not grant eligibility
  IF NOT COALESCE(v_require_active, FALSE) THEN
    RETURN COALESCE(v_allow_free, FALSE);
  END IF;

  -- Compute expiry cutoff
  IF COALESCE(v_expiry_enforced, TRUE) THEN
    v_cutoff := NOW() - (COALESCE(v_grace_days, 0) || ' days')::INTERVAL;
  ELSE
    v_cutoff := '-infinity'::TIMESTAMPTZ;
  END IF;

  -- Check for active, non-expired global subscription with allow_instahelp = true
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

  -- No qualifying subscription — eligible only when allow_free_vendors is explicitly on
  -- Default FALSE: missing config does not grant eligibility
  RETURN COALESCE(v_allow_free, FALSE);
END;
$$;

-- ── 3. get_instahelp_eligible_vendor_ids — corrected defaults ─────────────────
-- Changes from 20261105000014:
--   • COALESCE for allow_free_vendors setting read: 'true' → 'false'
--   • COALESCE(v_allow_free, TRUE) in the RETURN QUERY OR clause: → FALSE

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

  -- Module off: all active vendors eligible
  IF NOT COALESCE(v_enabled, FALSE) THEN
    RETURN QUERY SELECT id FROM vendors WHERE is_active = TRUE;
    RETURN;
  END IF;

  -- No subscription required + allow free vendors: all active vendors eligible
  IF NOT COALESCE(v_require_active, FALSE) AND COALESCE(v_allow_free, FALSE) THEN
    RETURN QUERY SELECT id FROM vendors WHERE is_active = TRUE;
    RETURN;
  END IF;

  -- Compute expiry cutoff
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
        -- Has free orders remaining (allowance > 0 and usage below limit)
        (
          COALESCE(v_free_allowance, 0) > 0
          AND COALESCE(
            (SELECT ifo.orders_used FROM vendor_instahelp_free_orders ifo
             WHERE ifo.vendor_id = vr.id),
            0
          ) < v_free_allowance
        )
        OR
        -- Has active, non-expired global subscription with allow_instahelp = true
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
        -- No active subscription + allow_free_vendors explicitly enabled by admin
        -- COALESCE(v_allow_free, FALSE): missing setting does not grant eligibility
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

GRANT EXECUTE ON FUNCTION get_instahelp_eligible_vendor_ids()                TO authenticated;
GRANT EXECUTE ON FUNCTION check_vendor_instahelp_eligibility(UUID)           TO authenticated;
