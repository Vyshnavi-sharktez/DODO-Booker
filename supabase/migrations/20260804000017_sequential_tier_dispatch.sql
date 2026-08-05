-- ── Sequential Tier Dispatch & Timeout Escalation ───────────────────────────

-- 1. Create dispatch_settings table
CREATE TABLE IF NOT EXISTS public.dispatch_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  is_tier_dispatch_enabled BOOLEAN NOT NULL DEFAULT true,
  tier_timeout_seconds INT NOT NULL DEFAULT 60,
  max_attempts_per_tier INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Seed default settings row if missing
INSERT INTO public.dispatch_settings (id, is_tier_dispatch_enabled, tier_timeout_seconds, max_attempts_per_tier)
SELECT gen_random_uuid(), true, 60, 1
WHERE NOT EXISTS (SELECT 1 FROM public.dispatch_settings);

-- RLS for dispatch_settings
ALTER TABLE public.dispatch_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow anon read dispatch_settings" ON public.dispatch_settings;
CREATE POLICY "Allow anon read dispatch_settings" ON public.dispatch_settings FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow auth all dispatch_settings" ON public.dispatch_settings;
CREATE POLICY "Allow auth all dispatch_settings" ON public.dispatch_settings FOR ALL USING (auth.role() = 'authenticated');

-- 2. Extend bookings table with dispatch tracking columns
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS dispatch_status TEXT DEFAULT 'idle',
  ADD COLUMN IF NOT EXISTS current_dispatch_tier_priority INT,
  ADD COLUMN IF NOT EXISTS dispatch_started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_dispatch_attempt_at TIMESTAMPTZ;

-- 3. Create booking_assignments table
CREATE TABLE IF NOT EXISTS public.booking_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  vendor_id UUID REFERENCES public.vendors(id) ON DELETE CASCADE,
  tier_id UUID REFERENCES public.vendor_tiers(id) ON DELETE SET NULL,
  tier_priority INT,
  attempt_number INT NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'accepted', 'rejected', 'timed_out'
  rejection_reason TEXT,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_booking_assignments_booking_id ON public.booking_assignments (booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_assignments_vendor_id ON public.booking_assignments (vendor_id);
CREATE INDEX IF NOT EXISTS idx_booking_assignments_status ON public.booking_assignments (status);

-- RLS for booking_assignments
ALTER TABLE public.booking_assignments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow anon read booking_assignments" ON public.booking_assignments;
CREATE POLICY "Allow anon read booking_assignments" ON public.booking_assignments FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow auth all booking_assignments" ON public.booking_assignments;
CREATE POLICY "Allow auth all booking_assignments" ON public.booking_assignments FOR ALL USING (auth.role() = 'authenticated');

-- Realtime setup for booking_assignments
ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_assignments;

-- 4. Stored Procedure: dispatch_booking_next_tier(p_booking_id UUID)
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

  -- Abort if booking is already accepted, in_progress, or completed
  IF v_booking.status IN ('accepted', 'in_progress', 'completed', 'awaiting_verification') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_accepted', 'status', v_booking.status);
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
        AND status IN ('rejected', 'timed_out', 'pending', 'accepted')
    )
  ORDER BY COALESCE(vt.priority, 99999) ASC, v.rating DESC NULLS LAST, v.business_name ASC
  LIMIT 1;

  -- If an eligible vendor candidate is found:
  IF v_candidate.vendor_id IS NOT NULL THEN
    -- Mark any previous pending assignment records as timed_out
    UPDATE public.booking_assignments
    SET status = 'timed_out', responded_at = now()
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
    SET status = 'timed_out', responded_at = now()
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

-- 5. Stored Procedure: process_pending_dispatch_escalations()
CREATE OR REPLACE FUNCTION public.process_pending_dispatch_escalations()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_booking_id UUID;
  v_timeout INT := 60;
  v_count INT := 0;
BEGIN
  SELECT COALESCE(tier_timeout_seconds, 60) INTO v_timeout
  FROM public.dispatch_settings
  LIMIT 1;

  FOR v_booking_id IN
    SELECT id
    FROM public.bookings
    WHERE status = 'assigned'
      AND dispatch_status = 'dispatching'
      AND last_dispatch_attempt_at IS NOT NULL
      AND (last_dispatch_attempt_at + (v_timeout || ' seconds')::INTERVAL) < now()
  LOOP
    PERFORM public.dispatch_booking_next_tier(v_booking_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- 6. Trigger: Automatically update booking_assignments status when vendor accepts/rejects
CREATE OR REPLACE FUNCTION public.fn_on_booking_assignment_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Vendor accepted
  IF NEW.status = 'accepted' AND OLD.status = 'assigned' THEN
    UPDATE public.booking_assignments
    SET status = 'accepted', responded_at = now()
    WHERE booking_id = NEW.id AND vendor_id = NEW.vendor_id AND status = 'pending';

    UPDATE public.bookings
    SET dispatch_status = 'accepted'
    WHERE id = NEW.id;
  END IF;

  -- Vendor rejected
  IF NEW.status = 'rejected' AND OLD.status = 'assigned' THEN
    UPDATE public.booking_assignments
    SET status = 'rejected', rejection_reason = NEW.rejection_reason, responded_at = now()
    WHERE booking_id = NEW.id AND (vendor_id = OLD.vendor_id OR vendor_id = NEW.vendor_id) AND status = 'pending';

    -- Immediately trigger next tier escalation
    PERFORM public.dispatch_booking_next_tier(NEW.id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_booking_assignment_status_change ON public.bookings;
CREATE TRIGGER trg_on_booking_assignment_status_change
AFTER UPDATE OF status ON public.bookings
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION public.fn_on_booking_assignment_status_change();
