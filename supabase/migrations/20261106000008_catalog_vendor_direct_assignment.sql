-- ── Catalog Vendor Direct Assignment ─────────────────────────────────────────
--
-- Vendor Catalog bookings must be assigned directly to the vendor who owns the
-- catalog item. They must never enter the sequential tier dispatch system nor be
-- re-dispatched to other vendors if the owning vendor rejects the booking.
--
-- Changes:
--  1. Add booking_source column to bookings (NULL = normal flow)
--  2. RPC: validate_catalog_vendor_for_booking — pre-flight check before INSERT
--  3. Update dispatch_booking_next_tier — early-exit for catalog_vendor bookings
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. booking_source column ─────────────────────────────────────────────────

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS booking_source TEXT
    CHECK (booking_source IN ('manual', 'preferred_vendor', 'instahelp', 'catalog_vendor'));

-- ── 2. RPC: validate_catalog_vendor_for_booking ───────────────────────────────
-- Called by the customer app before creating a catalog vendor booking.
-- Returns { valid: true } or { valid: false, reason, message }.

DROP FUNCTION IF EXISTS public.validate_catalog_vendor_for_booking(UUID, TEXT);

CREATE FUNCTION public.validate_catalog_vendor_for_booking(
  p_vendor_id      UUID,
  p_payment_method TEXT DEFAULT 'cash'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vendor             RECORD;
  v_is_cod             BOOLEAN;
  v_cod_eligible       BOOLEAN;
  v_sub_enabled        BOOLEAN;
  v_has_any_active_sub BOOLEAN;
  v_has_allowed_sub    BOOLEAN;
BEGIN
  SELECT id, is_active, business_name
  INTO v_vendor
  FROM public.vendors
  WHERE id = p_vendor_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'valid',   false,
      'reason',  'vendor_not_found',
      'message', 'Service provider not found.'
    );
  END IF;

  IF NOT v_vendor.is_active THEN
    RETURN jsonb_build_object(
      'valid',   false,
      'reason',  'vendor_inactive',
      'message', 'This service provider is no longer available.'
    );
  END IF;

  -- COD eligibility: mirrors check_vendor_cod_eligibility settings logic.
  v_is_cod := LOWER(COALESCE(p_payment_method, '')) IN ('cash', 'cod');
  IF v_is_cod THEN
    v_cod_eligible := public.check_vendor_cod_eligibility(p_vendor_id);
    IF NOT v_cod_eligible THEN
      RETURN jsonb_build_object(
        'valid',   false,
        'reason',  'cod_ineligible',
        'message', 'This service provider does not support cash payment. Please pay online.'
      );
    END IF;
  END IF;

  -- Subscription assignment permission: mirrors _vendorAssignmentBlockedProvider logic.
  -- Vendors with NO active subscription are allowed by default.
  -- Vendors with an active subscription that lacks allow_booking_assignment are blocked.
  SELECT COALESCE(setting_value = 'true', false) INTO v_sub_enabled
  FROM public.settings
  WHERE setting_key = 'subscription_enabled';

  IF v_sub_enabled THEN
    SELECT EXISTS(
      SELECT 1
      FROM public.vendor_subscriptions
      WHERE vendor_id      = p_vendor_id
        AND status         = 'active'
        AND expiry_date    > now()
        AND catalog_node_id IS NULL
    ) INTO v_has_any_active_sub;

    IF v_has_any_active_sub THEN
      SELECT EXISTS(
        SELECT 1
        FROM public.vendor_subscriptions  vs
        JOIN public.subscription_plans    sp ON sp.id = vs.plan_id
        WHERE vs.vendor_id      = p_vendor_id
          AND vs.status         = 'active'
          AND vs.expiry_date    > now()
          AND vs.catalog_node_id IS NULL
          AND (
            (sp.permissions->>'allow_booking_assignment')::BOOLEAN = true
            OR (sp.permissions->>'allow_assignment')::BOOLEAN       = true
          )
      ) INTO v_has_allowed_sub;

      IF NOT v_has_allowed_sub THEN
        RETURN jsonb_build_object(
          'valid',   false,
          'reason',  'subscription_ineligible',
          'message', 'This service provider is currently unavailable for new bookings.'
        );
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('valid', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.validate_catalog_vendor_for_booking(UUID, TEXT)
  TO anon, authenticated;

-- ── 3. Update dispatch_booking_next_tier — guard against catalog_vendor bookings

CREATE OR REPLACE FUNCTION public.dispatch_booking_next_tier(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_booking            RECORD;
  v_candidate          RECORD;
  v_attempt_count      INT := 0;
  v_tier_timeout       INT := 60;
  v_assignment_id      UUID;
  v_min_wallet         NUMERIC := 0;
  v_is_cod             BOOLEAN := FALSE;
  v_is_instahelp       BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v_booking
  FROM public.bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF v_booking IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

  IF v_booking.status IN ('accepted', 'in_progress', 'completed', 'awaiting_verification') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_accepted',
                              'status', v_booking.status);
  END IF;

  IF v_booking.dispatch_status IN ('manual', 'assigned_to_dodo_team') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'manual_assignment',
                              'message', 'Booking is manually assigned to a vendor or team');
  END IF;

  -- Catalog vendor bookings are assigned directly to the owning vendor and must
  -- never be dispatched to other vendors, even if the owning vendor rejects.
  IF v_booking.booking_source = 'catalog_vendor' THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason',  'catalog_vendor_booking',
      'message', 'This booking is directly assigned to the catalog service provider and cannot be dispatched to other vendors.'
    );
  END IF;

  SELECT COALESCE(tier_timeout_seconds, 60) INTO v_tier_timeout
  FROM public.dispatch_settings LIMIT 1;

  SELECT COALESCE(NULLIF(TRIM(setting_value), '')::NUMERIC, 0) INTO v_min_wallet
  FROM public.settings WHERE setting_key = 'wallet_minimum_balance';

  v_is_cod       := LOWER(COALESCE(v_booking.payment_method, '')) IN ('cash', 'cod');
  v_is_instahelp := EXISTS (
    SELECT 1 FROM public.instahelp_bookings WHERE booking_id = p_booking_id
  );

  SELECT COUNT(*) INTO v_attempt_count
  FROM public.booking_assignments
  WHERE booking_id = p_booking_id;

  -- ── Preferred vendor fast-path (InstaHelp only) ───────────────────────────
  IF v_is_instahelp THEN
    SELECT
      v.id          AS vendor_id,
      v.business_name,
      vt.id         AS tier_id,
      vt.name       AS tier_name,
      COALESCE(vt.priority, 99999) AS tier_priority
    INTO v_candidate
    FROM public.vendors v
    LEFT JOIN public.vendor_tiers vt ON v.tier_id = vt.id
    LEFT JOIN public.vendor_wallets vw ON vw.vendor_id = v.id
    WHERE v.is_active = TRUE
      AND v.is_online = TRUE
      AND v.is_preferred_vendor = TRUE
      AND (v_min_wallet <= 0 OR COALESCE(vw.available_balance, 0) >= v_min_wallet)
      AND (NOT v_is_cod OR public.check_vendor_cod_eligibility(v.id) = TRUE)
      AND public.check_vendor_instahelp_eligibility(v.id) = TRUE
      AND v.id NOT IN (
        SELECT vendor_id FROM public.booking_assignments
        WHERE booking_id = p_booking_id
          AND vendor_id IS NOT NULL
          AND status IN ('rejected', 'timed_out', 'pending', 'accepted', 'cancelled')
      )
    ORDER BY COALESCE(vt.priority, 99999) ASC, v.rating DESC NULLS LAST
    LIMIT 1;
  END IF;

  -- ── Normal tier-ordered candidate query ───────────────────────────────────
  IF v_candidate.vendor_id IS NULL THEN
    SELECT
      v.id          AS vendor_id,
      v.business_name,
      vt.id         AS tier_id,
      vt.name       AS tier_name,
      COALESCE(vt.priority, 99999) AS tier_priority
    INTO v_candidate
    FROM public.vendors v
    LEFT JOIN public.vendor_tiers vt ON v.tier_id = vt.id
    LEFT JOIN public.vendor_wallets vw ON vw.vendor_id = v.id
    WHERE v.is_active = TRUE
      AND v.is_online = TRUE
      AND (v_min_wallet <= 0 OR COALESCE(vw.available_balance, 0) >= v_min_wallet)
      AND (NOT v_is_cod        OR public.check_vendor_cod_eligibility(v.id)       = TRUE)
      AND (NOT v_is_instahelp  OR public.check_vendor_instahelp_eligibility(v.id) = TRUE)
      AND v.id NOT IN (
        SELECT vendor_id FROM public.booking_assignments
        WHERE booking_id = p_booking_id
          AND vendor_id IS NOT NULL
          AND status IN ('rejected', 'timed_out', 'pending', 'accepted', 'cancelled')
      )
    ORDER BY COALESCE(vt.priority, 99999) ASC, v.rating DESC NULLS LAST, v.business_name ASC
    LIMIT 1;
  END IF;

  -- ── Dispatch ──────────────────────────────────────────────────────────────
  IF v_candidate.vendor_id IS NOT NULL THEN
    UPDATE public.booking_assignments
    SET status       = 'timed_out',
        responded_at = LEAST(now(), assigned_at + (v_tier_timeout || ' seconds')::INTERVAL)
    WHERE booking_id = p_booking_id AND status = 'pending';

    INSERT INTO public.booking_assignments (
      booking_id, vendor_id, tier_id, tier_priority, attempt_number, status, assigned_at
    ) VALUES (
      p_booking_id, v_candidate.vendor_id, v_candidate.tier_id,
      v_candidate.tier_priority, v_attempt_count + 1, 'pending', NOW()
    ) RETURNING id INTO v_assignment_id;

    UPDATE public.bookings
    SET vendor_id                      = v_candidate.vendor_id,
        status                         = 'assigned',
        assignment_type                = 'External Vendor',
        dispatch_status                = 'dispatching',
        current_dispatch_tier_priority = v_candidate.tier_priority,
        dispatch_started_at            = COALESCE(dispatch_started_at, NOW()),
        last_dispatch_attempt_at       = NOW()
    WHERE id = p_booking_id;

    INSERT INTO public.notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'vendor', v_candidate.vendor_id,
      'New Booking Request',
      'New booking request #' || COALESCE(v_booking.booking_number, '') || '. Tap to review.',
      'vendor_assigned', 'booking', p_booking_id, FALSE, NOW()
    );

    RETURN jsonb_build_object(
      'success',        TRUE,
      'status',         'dispatching',
      'assignment_id',  v_assignment_id,
      'vendor_id',      v_candidate.vendor_id,
      'vendor_name',    v_candidate.business_name,
      'tier_name',      COALESCE(v_candidate.tier_name, 'Unranked'),
      'tier_priority',  v_candidate.tier_priority,
      'attempt_number', v_attempt_count + 1
    );
  ELSE
    UPDATE public.booking_assignments
    SET status       = 'timed_out',
        responded_at = LEAST(now(), assigned_at + (v_tier_timeout || ' seconds')::INTERVAL)
    WHERE booking_id = p_booking_id AND status = 'pending';

    UPDATE public.bookings
    SET dispatch_status = 'exhausted'
    WHERE id = p_booking_id;

    RETURN jsonb_build_object(
      'success', FALSE,
      'status',  'exhausted',
      'message', 'No eligible vendors available for dispatch'
    );
  END IF;
END;
$$;
