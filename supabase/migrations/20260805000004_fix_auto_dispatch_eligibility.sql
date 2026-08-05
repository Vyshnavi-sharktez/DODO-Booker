-- Migration: Fix auto-dispatch eligibility check to allow pending/idle bookings to initiate auto-dispatch

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

  -- Find highest-priority eligible candidate vendor NOT previously attempted
  SELECT
    v.id AS vendor_id,
    v.business_name,
    vt.id AS tier_id,
    vt.name AS tier_name,
    COALESCE(vt.priority, 99999) AS tier_priority
  INTO v_candidate
  FROM public.vendors v
  LEFT JOIN public.vendor_tiers vt ON v.tier_id = vt.id
  LEFT JOIN public.vendor_wallets vw ON vw.vendor_id = v.id
  WHERE v.is_active = true
    AND v.is_online = true
    AND (v_min_wallet <= 0 OR COALESCE(vw.available_balance, 0) >= v_min_wallet)
    AND (NOT v_is_cod OR check_vendor_cod_eligibility(v.id) = true)
    AND v.id NOT IN (
      SELECT vendor_id
      FROM public.booking_assignments
      WHERE booking_id = p_booking_id
        AND vendor_id IS NOT NULL
        AND status IN ('rejected', 'timed_out', 'pending', 'accepted', 'cancelled')
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
