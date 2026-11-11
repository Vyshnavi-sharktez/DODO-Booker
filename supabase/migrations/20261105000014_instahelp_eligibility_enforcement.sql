-- ─────────────────────────────────────────────────────────────────────────────
-- InstaHelp eligibility enforcement
--
-- Adds:
--   1. is_order_counted column on instahelp_bookings (dedup guard for counter)
--   2. check_vendor_instahelp_eligibility(UUID) → BOOLEAN
--        Reads all instahelp_subscription_* settings; returns TRUE when vendor
--        may receive InstaHelp bookings.  Called by trigger + dispatch.
--   3. get_instahelp_eligible_vendor_ids() → SETOF UUID
--        Returns every active vendor ID that passes eligibility — used by the
--        admin assignment dialog so it can compute the ineligible set client-side.
--   4. fn_enforce_instahelp_vendor_eligibility() trigger
--        Fires BEFORE UPDATE OF vendor_id on bookings; blocks assignment when
--        the booking is InstaHelp and the new vendor is ineligible.
--   5. dispatch_booking_next_tier() updated
--        Extends the existing candidate WHERE clause so the auto-dispatch engine
--        skips ineligible vendors for InstaHelp bookings.
--   6. fn_increment_instahelp_orders_used() trigger
--        Fires AFTER UPDATE OF status on bookings; increments orders_used in
--        vendor_instahelp_free_orders once per booking (guarded by is_order_counted).
--        Respects instahelp_subscription_order_counting_method setting:
--          'completed'  → count at booking completion
--          anything else → count at first vendor acceptance
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. is_order_counted column ───────────────────────────────────────────────

ALTER TABLE instahelp_bookings
  ADD COLUMN IF NOT EXISTS is_order_counted BOOLEAN NOT NULL DEFAULT FALSE;

-- ── 2. check_vendor_instahelp_eligibility ────────────────────────────────────

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
  -- Read all InstaHelp subscription settings in one query
  SELECT
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_enabled'            THEN setting_value END), 'false') = 'true',
    COALESCE(NULLIF(TRIM(COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_free_order_allowance' THEN setting_value END), '0')), ''), '0')::INT,
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_require_active'     THEN setting_value END), 'false') = 'true',
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_allow_free_vendors' THEN setting_value END), 'true')  = 'true',
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
    -- Vendor not in table → 0 used → eligible
    IF COALESCE(v_orders_used, 0) < v_free_allowance THEN
      RETURN TRUE;
    END IF;
    -- Free orders exhausted — fall through to subscription check
  END IF;

  -- No subscription required → allow based on allow_free_vendors flag
  IF NOT COALESCE(v_require_active, FALSE) THEN
    RETURN COALESCE(v_allow_free, TRUE);
  END IF;

  -- Compute expiry cutoff (expiry_date must be > now() - grace_days)
  IF COALESCE(v_expiry_enforced, TRUE) THEN
    v_cutoff := NOW() - (COALESCE(v_grace_days, 0) || ' days')::INTERVAL;
  ELSE
    v_cutoff := '-infinity'::TIMESTAMPTZ;
  END IF;

  -- Check for active, non-expired subscription with allow_instahelp = true
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

  -- No qualifying subscription — eligible only when allow_free_vendors is on
  RETURN COALESCE(v_allow_free, TRUE);
END;
$$;

-- ── 3. get_instahelp_eligible_vendor_ids ─────────────────────────────────────
-- Returns the set of active vendor IDs eligible for InstaHelp booking assignment.
-- Called by the admin panel assignment dialog to compute the ineligible vendor set.

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
    COALESCE(MAX(CASE WHEN setting_key = 'instahelp_subscription_allow_free_vendors' THEN setting_value END), 'true')  = 'true',
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
  IF NOT COALESCE(v_require_active, FALSE) AND COALESCE(v_allow_free, TRUE) THEN
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
        -- No active subscription + allow_free_vendors = true
        (
          COALESCE(v_allow_free, TRUE)
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

-- ── 4. Assignment trigger ─────────────────────────────────────────────────────
-- Fires BEFORE UPDATE OF vendor_id on bookings.
-- Blocks any vendor assignment to an InstaHelp booking when the vendor is ineligible.
-- Does not interfere with non-InstaHelp bookings, COD checks, or team assignments.

CREATE OR REPLACE FUNCTION fn_enforce_instahelp_vendor_eligibility()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- No vendor being assigned — nothing to check
  IF NEW.vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- On UPDATE: skip if vendor_id did not actually change
  IF TG_OP = 'UPDATE'
     AND OLD.vendor_id IS NOT DISTINCT FROM NEW.vendor_id THEN
    RETURN NEW;
  END IF;

  -- Only applies to InstaHelp bookings
  IF NOT EXISTS (
    SELECT 1 FROM instahelp_bookings WHERE booking_id = NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  IF NOT check_vendor_instahelp_eligibility(NEW.vendor_id) THEN
    RAISE EXCEPTION
      'Vendor % is not eligible to receive InstaHelp bookings. '
      'The vendor must have an active subscription with InstaHelp permission '
      'or free InstaHelp orders remaining.',
      NEW.vendor_id
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_instahelp_vendor_eligibility ON bookings;
CREATE TRIGGER trg_enforce_instahelp_vendor_eligibility
  BEFORE UPDATE OF vendor_id ON bookings
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_instahelp_vendor_eligibility();

-- ── 5. dispatch_booking_next_tier — updated with InstaHelp eligibility ────────
-- Full replacement of the function (mirrors 20260805000004 + InstaHelp check).

CREATE OR REPLACE FUNCTION public.dispatch_booking_next_tier(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_booking       RECORD;
  v_candidate     RECORD;
  v_attempt_count INT := 0;
  v_tier_timeout  INT := 60;
  v_assignment_id UUID;
  v_min_wallet    NUMERIC := 0;
  v_is_cod        BOOLEAN := FALSE;
  v_is_instahelp  BOOLEAN := FALSE;
BEGIN
  -- Lock booking row for atomic concurrency control
  SELECT * INTO v_booking
  FROM public.bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF v_booking IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

  -- Abort if already accepted, in_progress, completed, or awaiting_verification
  IF v_booking.status IN ('accepted', 'in_progress', 'completed', 'awaiting_verification') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_accepted',
                              'status', v_booking.status);
  END IF;

  -- Abort if manually assigned
  IF v_booking.dispatch_status IN ('manual', 'assigned_to_dodo_team') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'manual_assignment',
                              'message', 'Booking is manually assigned to a vendor or team');
  END IF;

  -- Get dispatch timeout
  SELECT COALESCE(tier_timeout_seconds, 60) INTO v_tier_timeout
  FROM public.dispatch_settings LIMIT 1;

  -- Get minimum wallet balance
  SELECT COALESCE(NULLIF(TRIM(setting_value), '')::NUMERIC, 0) INTO v_min_wallet
  FROM public.settings WHERE setting_key = 'wallet_minimum_balance';

  -- Classify booking
  v_is_cod       := LOWER(COALESCE(v_booking.payment_method, '')) IN ('cash', 'cod');
  v_is_instahelp := EXISTS (
    SELECT 1 FROM public.instahelp_bookings WHERE booking_id = p_booking_id
  );

  -- Count existing attempts
  SELECT COUNT(*) INTO v_attempt_count
  FROM public.booking_assignments
  WHERE booking_id = p_booking_id;

  -- Find highest-priority eligible candidate not previously attempted
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
    AND (NOT v_is_cod        OR public.check_vendor_cod_eligibility(v.id)        = TRUE)
    AND (NOT v_is_instahelp  OR public.check_vendor_instahelp_eligibility(v.id)  = TRUE)
    AND v.id NOT IN (
      SELECT vendor_id
      FROM public.booking_assignments
      WHERE booking_id = p_booking_id
        AND vendor_id IS NOT NULL
        AND status IN ('rejected', 'timed_out', 'pending', 'accepted', 'cancelled')
    )
  ORDER BY COALESCE(vt.priority, 99999) ASC, v.rating DESC NULLS LAST, v.business_name ASC
  LIMIT 1;

  IF v_candidate.vendor_id IS NOT NULL THEN
    -- Time out any pending assignment record
    UPDATE public.booking_assignments
    SET status       = 'timed_out',
        responded_at = LEAST(now(), assigned_at + (v_tier_timeout || ' seconds')::INTERVAL)
    WHERE booking_id = p_booking_id AND status = 'pending';

    -- Insert new assignment attempt
    INSERT INTO public.booking_assignments (
      booking_id, vendor_id, tier_id, tier_priority, attempt_number, status, assigned_at
    ) VALUES (
      p_booking_id, v_candidate.vendor_id, v_candidate.tier_id,
      v_candidate.tier_priority, v_attempt_count + 1, 'pending', NOW()
    ) RETURNING id INTO v_assignment_id;

    -- Update booking
    UPDATE public.bookings
    SET vendor_id                    = v_candidate.vendor_id,
        status                       = 'assigned',
        assignment_type              = 'External Vendor',
        dispatch_status              = 'dispatching',
        current_dispatch_tier_priority = v_candidate.tier_priority,
        dispatch_started_at          = COALESCE(dispatch_started_at, NOW()),
        last_dispatch_attempt_at     = NOW()
    WHERE id = p_booking_id;

    -- In-app notification for vendor
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
    -- All eligible vendors exhausted
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

-- ── 6. Order-count increment trigger ─────────────────────────────────────────
-- Increments vendor_instahelp_free_orders.orders_used once per InstaHelp booking.
-- The is_order_counted flag on instahelp_bookings prevents double-counting.
-- Counting method (from settings):
--   'completed'  → fires when booking.status transitions to 'completed'
--   anything else → fires when booking.status transitions to 'accepted'

CREATE OR REPLACE FUNCTION fn_increment_instahelp_orders_used()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_counting_method TEXT;
  v_target_status   TEXT;
BEGIN
  -- Read counting method (single settings row)
  SELECT COALESCE(setting_value, 'completed') INTO v_counting_method
  FROM settings WHERE setting_key = 'instahelp_subscription_order_counting_method';

  v_target_status := CASE
    WHEN COALESCE(v_counting_method, 'completed') = 'completed' THEN 'completed'
    ELSE 'accepted'
  END;

  -- Only fire on the target status transition
  IF NEW.status <> v_target_status OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Only for InstaHelp bookings not yet counted
  IF NOT EXISTS (
    SELECT 1 FROM instahelp_bookings
    WHERE booking_id = NEW.id AND is_order_counted = FALSE
  ) THEN
    RETURN NEW;
  END IF;

  -- Vendor must be assigned
  IF NEW.vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Mark as counted first (prevents double-fire if trigger runs again)
  UPDATE instahelp_bookings
  SET is_order_counted = TRUE
  WHERE booking_id = NEW.id;

  -- Upsert orders_used counter
  INSERT INTO vendor_instahelp_free_orders (vendor_id, orders_used)
  VALUES (NEW.vendor_id, 1)
  ON CONFLICT (vendor_id)
  DO UPDATE SET
    orders_used = vendor_instahelp_free_orders.orders_used + 1,
    updated_at  = NOW();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_increment_instahelp_orders_used ON bookings;
CREATE TRIGGER trg_increment_instahelp_orders_used
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW EXECUTE FUNCTION fn_increment_instahelp_orders_used();

-- ── RPC grant ─────────────────────────────────────────────────────────────────
-- Allow authenticated callers (admin panel) to invoke the eligible-vendor RPC.

GRANT EXECUTE ON FUNCTION get_instahelp_eligible_vendor_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION check_vendor_instahelp_eligibility(UUID) TO authenticated;
