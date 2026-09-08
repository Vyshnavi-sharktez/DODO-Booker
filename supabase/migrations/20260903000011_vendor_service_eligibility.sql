-- ── Vendor Service Eligibility ──────────────────────────────────────────────
-- Adds a vendor_services eligibility check to the two vendor-selection paths
-- that previously had no such filter:
--
--   1. dispatch_booking_next_tier      — auto-dispatch RPC
--   2. get_preferred_vendors_by_ids_and_location — preferred-vendor RPC
--
-- NEW RULE: a vendor is eligible only when they have an active vendor_services
-- row (vendor_services.is_active = true) for EVERY service in the booking.
--
-- Multi-service bookings are handled: the vendor must cover ALL booking_items
-- service_ids, not just one.
--
-- ALL existing eligibility conditions (is_active, is_online, wallet minimum,
-- COD eligibility, tier priority, rating, previous-attempt exclusion) are
-- preserved exactly — this is an additive change only.
-- ────────────────────────────────────────────────────────────────────────────


-- ── 1. Auto-dispatch: dispatch_booking_next_tier ──────────────────────────────
-- Adds one extra WHERE predicate (lines marked NEW) to the vendor SELECT.
-- Every other line of the function is reproduced verbatim.

CREATE OR REPLACE FUNCTION public.dispatch_booking_next_tier(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_booking RECORD;
  v_candidate RECORD;
  v_attempt_count INT := 0;
  v_tier_timeout INT := 60;
  v_assignment_id UUID;
  v_min_wallet NUMERIC := 0;
  v_is_cod BOOLEAN := false;
BEGIN
  -- Lock booking row for atomic concurrency control
  SELECT * INTO v_booking
  FROM public.bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF v_booking IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

  -- Abort if booking is already accepted, in_progress, completed, or awaiting_verification
  IF v_booking.status IN ('accepted', 'in_progress', 'completed', 'awaiting_verification') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_accepted', 'status', v_booking.status);
  END IF;

  -- Strictly abort if booking was manually assigned to a specific vendor ('manual' or 'assigned_to_dodo_team')
  IF v_booking.dispatch_status IN ('manual', 'assigned_to_dodo_team') THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'manual_assignment',
      'message', 'Booking is manually assigned to a vendor or team'
    );
  END IF;

  -- Get dispatch timeout setting
  SELECT COALESCE(tier_timeout_seconds, 60) INTO v_tier_timeout
  FROM public.dispatch_settings
  LIMIT 1;

  -- Get minimum wallet balance setting
  SELECT COALESCE(NULLIF(TRIM(setting_value), '')::NUMERIC, 0) INTO v_min_wallet
  FROM public.settings WHERE setting_key = 'wallet_minimum_balance';

  -- Check if booking is COD / cash payment
  v_is_cod := LOWER(COALESCE(v_booking.payment_method, '')) IN ('cash', 'cod');

  -- Count existing attempts for this booking
  SELECT COUNT(*) INTO v_attempt_count
  FROM public.booking_assignments
  WHERE booking_id = p_booking_id;

  -- Find highest-priority eligible candidate vendor NOT previously attempted.
  -- All original conditions preserved; one new condition added (service check).
  SELECT
    v.id AS vendor_id,
    v.business_name,
    vt.id AS tier_id,
    vt.name AS tier_name,
    COALESCE(vt.priority, 99999) AS tier_priority
  INTO v_candidate
  FROM public.vendors v
  LEFT JOIN public.vendor_tiers  vt ON vt.id = v.tier_id
  LEFT JOIN public.vendor_wallets vw ON vw.vendor_id = v.id
  WHERE v.is_active = true
    AND v.is_online = true
    AND (v_min_wallet <= 0 OR COALESCE(vw.available_balance, 0) >= v_min_wallet)
    AND (NOT v_is_cod OR public.check_vendor_cod_eligibility(v.id) = true)
    AND v.id NOT IN (
      SELECT vendor_id
      FROM public.booking_assignments
      WHERE booking_id = p_booking_id
        AND vendor_id IS NOT NULL
        AND status IN ('rejected', 'timed_out', 'pending', 'accepted', 'cancelled')
    )
    -- NEW: vendor must provide every service in this booking
    AND NOT EXISTS (
      SELECT 1
      FROM public.booking_items bi
      WHERE bi.booking_id = p_booking_id
        AND NOT EXISTS (
          SELECT 1
          FROM public.vendor_services vs
          WHERE vs.vendor_id = v.id
            AND vs.service_id = bi.service_id
            AND vs.is_active  = true
        )
    )
  ORDER BY COALESCE(vt.priority, 99999) ASC, v.rating DESC NULLS LAST, v.business_name ASC
  LIMIT 1;

  -- If an eligible vendor candidate is found:
  IF v_candidate.vendor_id IS NOT NULL THEN
    -- Mark any previous pending assignment records as timed_out
    UPDATE public.booking_assignments
    SET status = 'timed_out',
        responded_at = LEAST(now(), assigned_at + (v_tier_timeout || ' seconds')::INTERVAL)
    WHERE booking_id = p_booking_id AND status = 'pending';

    -- Insert new assignment attempt record
    INSERT INTO public.booking_assignments (
      booking_id,
      vendor_id,
      tier_id,
      tier_priority,
      attempt_number,
      status,
      assigned_at
    ) VALUES (
      p_booking_id,
      v_candidate.vendor_id,
      v_candidate.tier_id,
      v_candidate.tier_priority,
      v_attempt_count + 1,
      'pending',
      now()
    ) RETURNING id INTO v_assignment_id;

    -- Update booking status to assigned & set dispatch metrics
    UPDATE public.bookings
    SET
      vendor_id = v_candidate.vendor_id,
      status = 'assigned',
      assignment_type = 'External Vendor',
      dispatch_status = 'dispatching',
      current_dispatch_tier_priority = v_candidate.tier_priority,
      dispatch_started_at = COALESCE(dispatch_started_at, now()),
      last_dispatch_attempt_at = now()
    WHERE id = p_booking_id;

    -- Insert in-app notification for vendor
    INSERT INTO public.notifications (
      user_type,
      user_id,
      title,
      message,
      notification_type,
      entity_type,
      entity_id,
      is_read,
      created_at
    ) VALUES (
      'vendor',
      v_candidate.vendor_id,
      'New Booking Request',
      'New booking request #' || COALESCE(v_booking.booking_number, '') || '. Tap to review.',
      'vendor_assigned',
      'booking',
      p_booking_id,
      false,
      now()
    );

    RETURN jsonb_build_object(
      'success', true,
      'status', 'dispatching',
      'assignment_id', v_assignment_id,
      'vendor_id', v_candidate.vendor_id,
      'vendor_name', v_candidate.business_name,
      'tier_name', COALESCE(v_candidate.tier_name, 'Unranked'),
      'tier_priority', v_candidate.tier_priority,
      'attempt_number', v_attempt_count + 1
    );
  ELSE
    -- All eligible vendors exhausted
    UPDATE public.booking_assignments
    SET status = 'timed_out',
        responded_at = LEAST(now(), assigned_at + (v_tier_timeout || ' seconds')::INTERVAL)
    WHERE booking_id = p_booking_id AND status = 'pending';

    UPDATE public.bookings
    SET dispatch_status = 'exhausted'
    WHERE id = p_booking_id;

    RETURN jsonb_build_object(
      'success', false,
      'status', 'exhausted',
      'message', 'No eligible vendors available for dispatch'
    );
  END IF;
END;
$$;


-- ── 2. Preferred vendor: get_preferred_vendors_by_ids_and_location ────────────
-- Adds an optional p_service_ids UUID[] parameter.  When provided, vendors
-- that do not have an active vendor_services row for every listed service_id
-- are excluded.  Existing callers that omit the parameter (NULL default)
-- behave identically to before.

CREATE OR REPLACE FUNCTION public.get_preferred_vendors_by_ids_and_location(
  p_vendor_ids  TEXT[],
  p_lat         FLOAT8  DEFAULT NULL,
  p_lng         FLOAT8  DEFAULT NULL,
  p_vendor_fees JSONB   DEFAULT NULL,
  p_service_ids UUID[]  DEFAULT NULL   -- NEW: if set, vendor must cover all IDs
)
RETURNS TABLE (
  id                   UUID,
  business_name        TEXT,
  rating               NUMERIC,
  preferred_vendor_fee NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT sub.id, sub.business_name, sub.rating, sub.preferred_vendor_fee
  FROM (
    SELECT DISTINCT
      v.id,
      v.business_name,
      v.rating::NUMERIC                                             AS rating,
      COALESCE(
        (p_vendor_fees->>(v.id::TEXT))::NUMERIC,
        v.preferred_vendor_fee::NUMERIC
      )                                                             AS preferred_vendor_fee
    FROM  public.vendors                         v
    LEFT JOIN public.vendor_serving_area_assignments vsaa
           ON vsaa.vendor_id     = v.id
    LEFT JOIN public.vendor_serving_areas            vsa
           ON vsa.id             = vsaa.serving_area_id
    WHERE v.id = ANY(p_vendor_ids::UUID[])
      AND v.is_active = true
      AND (
            p_lat IS NULL
         OR p_lng IS NULL
         OR (
              vsa.is_active = true
              AND (
                    2.0 * 6371.0 * asin(sqrt(
                      power(sin(radians((vsa.latitude  - p_lat)  / 2.0)), 2) +
                      cos(radians(p_lat)) * cos(radians(vsa.latitude)) *
                      power(sin(radians((vsa.longitude - p_lng) / 2.0)), 2)
                    ))
                  ) <= vsa.radius_km
            )
      )
      -- NEW: vendor must have an active vendor_services row for every requested service
      AND (
            p_service_ids IS NULL
         OR NOT EXISTS (
              SELECT 1
              FROM unnest(p_service_ids) AS req(service_id)
              WHERE NOT EXISTS (
                SELECT 1
                FROM public.vendor_services vs
                WHERE vs.vendor_id  = v.id
                  AND vs.service_id = req.service_id
                  AND vs.is_active  = true
              )
            )
      )
  ) sub
  ORDER BY sub.rating DESC NULLS LAST, sub.business_name;
$$;
