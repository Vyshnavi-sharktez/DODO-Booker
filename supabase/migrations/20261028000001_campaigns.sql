-- ── Promotional Campaigns ─────────────────────────────────────────────────────
--
-- SMS (and future WhatsApp) promotional campaign management.
-- Completely separate from:
--   • send-sms Edge Function   (OTP only, Auth hook, untouched)
--   • broadcast_notifications  (FCM push only, untouched)
--
-- New tables:
--   campaigns           — one row per campaign; tracks status, counts, failure info
--   campaign_opt_outs   — per-phone opt-out registry (channel-scoped)
--
-- New RPCs:
--   get_campaign_recipient_count  — returns count + masked sample; no phones to browser
--   create_campaign               — saves draft, returns UUID
--   reset_campaign_to_draft       — explicit retry action for failed campaigns only
--   _get_campaign_phones          — service_role only; returns actual phone list for Edge Function
--
-- Security:
--   All admin-facing RPCs enforce is_active_admin().
--   Phone numbers are NEVER returned to the browser from any public RPC.
--   is_test_mode defaults TRUE — admin must explicitly disable test mode for live sends.
--   _get_campaign_phones: double-gated (GRANT + runtime auth.role() check), service_role only.
--
-- MSG91 integration:
--   Uses the Flow API (/api/v5/flow), not the OTP endpoint.
--   Reuses existing sms:msg91:api_key Vault secret (no new secrets needed).
--   Requires two new extra_config fields on sms_provider_configs:
--     test_phone           — safe target for test campaigns (configured in SMS Config page)
--     (template_id is stored per-campaign in campaigns.template_id)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── campaigns ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.campaigns (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT        NOT NULL,
  channel           TEXT        NOT NULL
                                CHECK (channel IN ('sms', 'whatsapp')),
  message           TEXT        NOT NULL DEFAULT '',
  template_id       TEXT        NOT NULL DEFAULT '',
  template_language TEXT        NOT NULL DEFAULT 'en',
  targeting_type    TEXT        NOT NULL DEFAULT 'all'
                                CHECK (targeting_type IN ('all', 'city', 'booked_service', 'booked_category')),
  targeting_value   TEXT,
  targeting_label   TEXT,
  -- SAFETY: defaults TRUE. Campaigns start in test mode; admin must opt out for live sends.
  is_test_mode      BOOLEAN     NOT NULL DEFAULT TRUE,
  status            TEXT        NOT NULL DEFAULT 'draft'
                                CHECK (status IN ('draft', 'sending', 'sent', 'failed', 'cancelled')),
  estimated_count   INT,
  recipient_count   INT         NOT NULL DEFAULT 0,
  -- sent_count = messages submitted to provider (NOT delivery confirmed)
  sent_count        INT         NOT NULL DEFAULT 0,
  failed_count      INT         NOT NULL DEFAULT 0,
  -- Up to 20 failure reasons; never stores phone numbers
  failure_summary   JSONB,
  created_by        UUID        REFERENCES public.admin_users(id) ON DELETE SET NULL,
  sent_at           TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION fn_campaigns_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_campaigns_updated_at ON public.campaigns;
CREATE TRIGGER trg_campaigns_updated_at
  BEFORE UPDATE ON public.campaigns
  FOR EACH ROW EXECUTE FUNCTION fn_campaigns_updated_at();

ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "campaigns_admin_all" ON public.campaigns;
CREATE POLICY "campaigns_admin_all"
  ON public.campaigns FOR ALL
  TO authenticated
  USING     (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

ALTER PUBLICATION supabase_realtime ADD TABLE public.campaigns;

-- ── campaign_opt_outs ─────────────────────────────────────────────────────────
-- Stores opted-out phone numbers per channel.
-- Phone is the key (not customer_id) because opt-out follows the number, not the account.

CREATE TABLE IF NOT EXISTS public.campaign_opt_outs (
  phone        TEXT        NOT NULL,
  channel      TEXT        NOT NULL
               CHECK (channel IN ('sms', 'whatsapp', 'all')),
  opted_out_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  added_by     UUID        REFERENCES public.admin_users(id) ON DELETE SET NULL,
  PRIMARY KEY (phone, channel)
);

ALTER TABLE public.campaign_opt_outs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "opt_outs_admin_all" ON public.campaign_opt_outs;
CREATE POLICY "opt_outs_admin_all"
  ON public.campaign_opt_outs FOR ALL
  TO authenticated
  USING     (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- ── get_campaign_recipient_count ──────────────────────────────────────────────
-- Returns eligible recipient count and up to 5 masked samples.
-- Phone numbers are NEVER returned in plaintext — last 4 digits replaced with XXXX.
-- Excludes: opted-out numbers, NULL/empty phones, duplicates.
-- Targeting logic mirrors send_broadcast_notification.

CREATE OR REPLACE FUNCTION public.get_campaign_recipient_count(
  p_channel         TEXT,
  p_targeting_type  TEXT    DEFAULT 'all',
  p_targeting_value TEXT    DEFAULT NULL
)
RETURNS TABLE (recipient_count INT, sample_masked TEXT[])
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phones TEXT[];
  v_count  INT;
  v_sample TEXT[];
BEGIN
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'admin authorisation required';
  END IF;

  SELECT ARRAY_AGG(DISTINCT au.phone)
  INTO v_phones
  FROM public.customers c
  JOIN auth.users au ON au.id = c.auth_user_id
  WHERE c.is_active = TRUE
    AND au.phone IS NOT NULL
    AND length(trim(au.phone)) >= 8
    AND NOT EXISTS (
      SELECT 1 FROM public.campaign_opt_outs coo
      WHERE coo.phone = au.phone
        AND coo.channel IN (p_channel, 'all')
    )
    AND CASE p_targeting_type
      WHEN 'all' THEN TRUE
      WHEN 'city' THEN EXISTS (
        SELECT 1 FROM public.customer_addresses ca
        WHERE ca.customer_id = c.id
          AND LOWER(ca.city) = LOWER(p_targeting_value)
      )
      WHEN 'booked_service' THEN
        p_targeting_value IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.bookings b
          JOIN public.booking_items bi ON bi.booking_id = b.id
          WHERE b.customer_id = c.id
            AND bi.service_id = p_targeting_value::UUID
        )
      WHEN 'booked_category' THEN
        p_targeting_value IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.bookings b
          JOIN public.booking_items bi ON bi.booking_id = b.id
          JOIN public.catalog_node_relationships cnr ON cnr.child_id = bi.service_id
          WHERE b.customer_id = c.id
            AND cnr.parent_id = p_targeting_value::UUID
        )
      ELSE FALSE
    END;

  v_count := COALESCE(ARRAY_LENGTH(v_phones, 1), 0);

  -- Masked sample: last 4 digits replaced with XXXX
  SELECT ARRAY_AGG(
    LEFT(p, GREATEST(length(p) - 4, 3)) || 'XXXX'
  )
  INTO v_sample
  FROM (
    SELECT UNNEST(v_phones[1:5]) AS p
  ) sub;

  RETURN QUERY
    SELECT v_count::INT,
           COALESCE(v_sample, ARRAY[]::TEXT[]);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_campaign_recipient_count(TEXT, TEXT, TEXT) TO authenticated;

-- ── create_campaign ───────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_campaign(
  p_name              TEXT,
  p_channel           TEXT,
  p_message           TEXT,
  p_template_id       TEXT,
  p_template_language TEXT,
  p_targeting_type    TEXT,
  p_targeting_value   TEXT,
  p_targeting_label   TEXT,
  p_is_test_mode      BOOLEAN,
  p_estimated_count   INT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
  v_id       UUID;
BEGIN
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'admin authorisation required';
  END IF;

  IF trim(p_name) = '' THEN
    RAISE EXCEPTION 'campaign name must not be empty';
  END IF;
  IF p_channel NOT IN ('sms', 'whatsapp') THEN
    RAISE EXCEPTION 'invalid channel: %', p_channel;
  END IF;
  IF trim(p_template_id) = '' THEN
    RAISE EXCEPTION 'template_id must not be empty';
  END IF;

  SELECT id INTO v_admin_id
  FROM public.admin_users
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  INSERT INTO public.campaigns (
    name, channel, message, template_id, template_language,
    targeting_type, targeting_value, targeting_label,
    is_test_mode, estimated_count, created_by
  ) VALUES (
    trim(p_name), p_channel, p_message, trim(p_template_id), COALESCE(p_template_language, 'en'),
    COALESCE(p_targeting_type, 'all'), p_targeting_value, p_targeting_label,
    p_is_test_mode, p_estimated_count, v_admin_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_campaign(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, INT) TO authenticated;

-- ── reset_campaign_to_draft ───────────────────────────────────────────────────
-- Explicit admin action to retry a failed campaign.
-- Only 'failed' campaigns may be reset — 'sending' and 'sent' are immutable.

CREATE OR REPLACE FUNCTION public.reset_campaign_to_draft(p_campaign_id UUID)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'admin authorisation required';
  END IF;

  UPDATE public.campaigns
  SET status          = 'draft',
      sent_count      = 0,
      failed_count    = 0,
      recipient_count = 0,
      failure_summary = NULL,
      sent_at         = NULL,
      updated_at      = now()
  WHERE id     = p_campaign_id
    AND status = 'failed';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Campaign not found or not in failed state. Only failed campaigns can be reset to draft.';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reset_campaign_to_draft(UUID) TO authenticated;

-- ── _get_campaign_phones ──────────────────────────────────────────────────────
-- Returns the actual phone number list for a campaign.
-- Called EXCLUSIVELY by Edge Functions holding a service_role JWT.
-- NEVER callable from the browser (double-gated: GRANT + runtime role check).
--
-- Test mode: returns only the single test_phone from sms_provider_configs.extra_config.
-- Live mode:  resolves all eligible customers, applies targeting + opt-out exclusion.

CREATE OR REPLACE FUNCTION public._get_campaign_phones(p_campaign_id UUID)
RETURNS TEXT[]
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phones TEXT[];
  v_camp   public.campaigns%ROWTYPE;
  v_test_phone TEXT;
BEGIN
  -- Layer 1: runtime role check (belt-and-suspenders with the GRANT below)
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Access denied: insufficient privileges';
  END IF;

  SELECT * INTO v_camp FROM public.campaigns WHERE id = p_campaign_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'campaign not found: %', p_campaign_id;
  END IF;

  -- Test mode: send only to the configured test phone
  IF v_camp.is_test_mode THEN
    SELECT (extra_config->>'test_phone')
    INTO   v_test_phone
    FROM   public.sms_provider_configs
    WHERE  provider    = 'msg91'
      AND  is_enabled  = TRUE
    LIMIT  1;

    IF v_test_phone IS NULL OR trim(v_test_phone) = '' THEN
      RAISE EXCEPTION 'Test mode is enabled but no test_phone is configured. '
                      'Add a test phone number in SMS / OTP Configuration.';
    END IF;

    RETURN ARRAY[trim(v_test_phone)];
  END IF;

  -- Live mode: resolve all eligible customers
  SELECT ARRAY_AGG(DISTINCT au.phone)
  INTO v_phones
  FROM public.customers c
  JOIN auth.users au ON au.id = c.auth_user_id
  WHERE c.is_active = TRUE
    AND au.phone IS NOT NULL
    AND length(trim(au.phone)) >= 8
    AND NOT EXISTS (
      SELECT 1 FROM public.campaign_opt_outs coo
      WHERE coo.phone = au.phone
        AND coo.channel IN (v_camp.channel, 'all')
    )
    AND CASE v_camp.targeting_type
      WHEN 'all' THEN TRUE
      WHEN 'city' THEN EXISTS (
        SELECT 1 FROM public.customer_addresses ca
        WHERE ca.customer_id = c.id
          AND LOWER(ca.city) = LOWER(v_camp.targeting_value)
      )
      WHEN 'booked_service' THEN
        v_camp.targeting_value IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.bookings b
          JOIN public.booking_items bi ON bi.booking_id = b.id
          WHERE b.customer_id = c.id
            AND bi.service_id = v_camp.targeting_value::UUID
        )
      WHEN 'booked_category' THEN
        v_camp.targeting_value IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.bookings b
          JOIN public.booking_items bi ON bi.booking_id = b.id
          JOIN public.catalog_node_relationships cnr ON cnr.child_id = bi.service_id
          WHERE b.customer_id = c.id
            AND cnr.parent_id = v_camp.targeting_value::UUID
        )
      ELSE FALSE
    END;

  RETURN COALESCE(v_phones, ARRAY[]::TEXT[]);
END;
$$;

-- Layer 2: GRANT restriction — anon and authenticated cannot call this function
REVOKE ALL   ON FUNCTION public._get_campaign_phones(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._get_campaign_phones(UUID) TO service_role;

-- ── New permissions ───────────────────────────────────────────────────────────

INSERT INTO public.permissions (name, description)
SELECT v.name, v.description
FROM (VALUES
  ('campaign.create', 'Create and send SMS and WhatsApp promotional campaigns'),
  ('campaign.read',   'View campaign history, delivery results, and opt-out list')
) AS v(name, description)
WHERE NOT EXISTS (
  SELECT 1 FROM public.permissions p WHERE p.name = v.name
);
