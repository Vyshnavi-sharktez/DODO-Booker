-- ─────────────────────────────────────────────────────────────────────────────
-- InstaHelp Preferred Vendor
--
-- Adds per-mode preferred-vendor configuration to instahelp_financial_config:
--   preferred_vendor_id    — vendor to dispatch to first for this mode (nullable)
--   preferred_vendor_price — admin-set price/payout for the preferred vendor
--
-- Auto-dispatch: when a preferred vendor is configured, check_vendor_instahelp_eligibility
-- returns TRUE, and they have not already been attempted for the booking, they are
-- selected before the normal tier-ordered candidate query.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.instahelp_financial_config
  ADD COLUMN IF NOT EXISTS preferred_vendor_id    UUID
    REFERENCES public.vendors(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS preferred_vendor_price NUMERIC(12,2)
    CHECK (preferred_vendor_price IS NULL OR preferred_vendor_price >= 0);

-- ── Updated dispatch_booking_next_tier ───────────────────────────────────────
-- Checks for a configured preferred vendor before the normal tier-ordered query.
-- Preferred vendor is used only when:
--   1. The booking is InstaHelp
--   2. preferred_vendor_id is set on the mode's financial config
--   3. The preferred vendor is active, online, and InstaHelp-eligible
--   4. The preferred vendor has not already been attempted for this booking

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
  v_preferred_vendor_id UUID;
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
    SELECT ifc.preferred_vendor_id INTO v_preferred_vendor_id
    FROM public.instahelp_bookings ib
    JOIN public.instahelp_financial_config ifc ON ifc.mode_id = ib.mode_id
    WHERE ib.booking_id = p_booking_id
    LIMIT 1;

    IF v_preferred_vendor_id IS NOT NULL THEN
      -- Use preferred vendor if active, online, eligible, and not yet attempted
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
      WHERE v.id = v_preferred_vendor_id
        AND v.is_active = TRUE
        AND v.is_online = TRUE
        AND (v_min_wallet <= 0 OR COALESCE(vw.available_balance, 0) >= v_min_wallet)
        AND (NOT v_is_cod OR public.check_vendor_cod_eligibility(v.id) = TRUE)
        AND public.check_vendor_instahelp_eligibility(v.id) = TRUE
        AND v.id NOT IN (
          SELECT vendor_id FROM public.booking_assignments
          WHERE booking_id = p_booking_id
            AND vendor_id IS NOT NULL
            AND status IN ('rejected', 'timed_out', 'pending', 'accepted', 'cancelled')
        );
    END IF;
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
