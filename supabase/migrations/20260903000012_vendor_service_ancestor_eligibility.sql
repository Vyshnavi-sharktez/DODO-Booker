-- ── Ancestor-Aware Vendor Service Eligibility ───────────────────────────────
-- Extends the vendor service eligibility check to support parent/ancestor node
-- matching.  A vendor who has registered "Carpet Cleaning" (non-bookable parent)
-- is now eligible for bookings of "Carpet Cleaning → Small/Medium/Large"
-- (bookable children).  Vendors registered at specific leaf nodes are unaffected.
--
-- WHAT THIS MIGRATION DOES
--   1. Adds get_node_ancestor_ids() — recursive ancestor walk via
--      catalog_node_relationships
--   2. Adds get_eligible_vendor_ids_for_services() — ancestor-aware vendor
--      eligibility set, for the admin manual-assignment dialog
--   3. Recreates dispatch_booking_next_tier with ancestor matching
--   4. Recreates get_preferred_vendors_by_ids_and_location with ancestor matching
--
-- WHAT IS PRESERVED EXACTLY
--   Subscription/COD eligibility, wallet requirements, active/online status,
--   tier/ranking, serving areas, previous dispatch attempts, assignment logic.
--   Existing leaf-node vendor registrations continue to match exactly as before
--   (the ancestor check is an OR addition, not a replacement).
--
-- SAFE TO RE-RUN: all functions use CREATE OR REPLACE.
-- ────────────────────────────────────────────────────────────────────────────


-- ── 1. get_node_ancestor_ids ─────────────────────────────────────────────────
-- Returns all ancestor UUIDs of p_node_id by walking catalog_node_relationships
-- upward.  Returns an empty array when the node has no parents (root node).
-- Used inline by eligibility checks to support parent-level service registration.

CREATE OR REPLACE FUNCTION public.get_node_ancestor_ids(p_node_id UUID)
RETURNS UUID[]
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH RECURSIVE anc AS (
    SELECT r.parent_id AS id
    FROM   public.catalog_node_relationships r
    WHERE  r.child_id = p_node_id

    UNION ALL

    SELECT r.parent_id
    FROM   public.catalog_node_relationships r
    JOIN   anc ON r.child_id = anc.id
  )
  SELECT COALESCE(
    ARRAY(SELECT DISTINCT id FROM anc),
    '{}'::UUID[]
  );
$$;


-- ── 2. get_eligible_vendor_ids_for_services ──────────────────────────────────
-- Returns the UUIDs of all vendors that have an active vendor_services row
-- covering EVERY service in p_service_ids, either by exact match or by having
-- registered an ancestor (parent/category) node.
--
-- Used by the admin booking-assignment dialog (Flutter _vendorServiceEligibleProvider)
-- so that the manual-assignment list respects ancestor-level registrations.

CREATE OR REPLACE FUNCTION public.get_eligible_vendor_ids_for_services(
  p_service_ids UUID[]
)
RETURNS UUID[]
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    ARRAY(
      SELECT DISTINCT vs.vendor_id
      FROM public.vendor_services vs
      WHERE vs.is_active = true
        AND NOT EXISTS (
          SELECT 1
          FROM unnest(p_service_ids) AS req(service_id)
          WHERE NOT EXISTS (
            SELECT 1
            FROM public.vendor_services vs2
            WHERE vs2.vendor_id = vs.vendor_id
              AND vs2.is_active = true
              AND (
                vs2.service_id = req.service_id
                OR vs2.service_id = ANY(public.get_node_ancestor_ids(req.service_id))
              )
          )
        )
    ),
    '{}'::UUID[]
  );
$$;


-- ── 3. dispatch_booking_next_tier ────────────────────────────────────────────
-- Full recreation with ancestor matching added to the service eligibility check.
-- All other logic (COD, wallet, tier priority, previous attempts) is unchanged.

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
  -- All original conditions preserved; ancestor matching added to service check.
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
    -- Vendor must provide every service in this booking (exact or ancestor match).
    AND NOT EXISTS (
      SELECT 1
      FROM public.booking_items bi
      WHERE bi.booking_id = p_booking_id
        AND NOT EXISTS (
          SELECT 1
          FROM public.vendor_services vs
          WHERE vs.vendor_id = v.id
            AND vs.is_active  = true
            AND (
              vs.service_id = bi.service_id
              OR vs.service_id = ANY(public.get_node_ancestor_ids(bi.service_id))
            )
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


-- ── 4. get_preferred_vendors_by_ids_and_location ─────────────────────────────
-- Full recreation with ancestor matching added to the service eligibility check.
-- All other logic (location radius, is_active, rating sort) is unchanged.

CREATE OR REPLACE FUNCTION public.get_preferred_vendors_by_ids_and_location(
  p_vendor_ids  TEXT[],
  p_lat         FLOAT8  DEFAULT NULL,
  p_lng         FLOAT8  DEFAULT NULL,
  p_vendor_fees JSONB   DEFAULT NULL,
  p_service_ids UUID[]  DEFAULT NULL
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
      -- Vendor must have an active vendor_services row for every requested service
      -- (exact match or ancestor/parent node match).
      AND (
            p_service_ids IS NULL
         OR NOT EXISTS (
              SELECT 1
              FROM unnest(p_service_ids) AS req(service_id)
              WHERE NOT EXISTS (
                SELECT 1
                FROM public.vendor_services vs
                WHERE vs.vendor_id  = v.id
                  AND vs.is_active  = true
                  AND (
                    vs.service_id = req.service_id
                    OR vs.service_id = ANY(public.get_node_ancestor_ids(req.service_id))
                  )
              )
            )
      )
  ) sub
  ORDER BY sub.rating DESC NULLS LAST, sub.business_name;
$$;
