-- ── AMC Booking Expiry Enforcement ────────────────────────────────────────────
--
-- 1. BEFORE INSERT trigger on bookings — backend enforcement layer (D5).
--    Calls amc_contract_is_bookable() and rejects new AMC bookings if the
--    contract is expired, inactive, or invalid.
--    BEFORE INSERT only: existing bookings (created while the contract was
--    valid) are never blocked — they remain valid and can be completed even
--    after the contract expires (locked business rule).
--
-- 2. Revised fn_amc_visit_completed — preserves contract status correctly:
--    a. 'completed' when all visits are exhausted (takes precedence over all).
--    b. 'cancellation_requested' is preserved; never overridden by 'active'
--       or 'expired' (D3 + pre-existing bug fix).
--    c. 'expired' when expires_at < now() and visits remain (lazy expiry
--       path; also stops auto-creation of next visit for expired contracts).
--    d. 'active' for the normal case.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Booking INSERT enforcement ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_check_amc_bookable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_amc = true AND NEW.amc_contract_id IS NOT NULL THEN
    IF NOT public.amc_contract_is_bookable(NEW.amc_contract_id) THEN
      RAISE EXCEPTION
        'amc_contract_not_bookable: AMC contract % is expired, inactive, or invalid',
        NEW.amc_contract_id
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_amc_bookable ON public.bookings;

CREATE TRIGGER trg_check_amc_bookable
  BEFORE INSERT ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_check_amc_bookable();

-- ── 2. Revised fn_amc_visit_completed ─────────────────────────────────────────
--
-- Replaces the version from 20260730000007_amc_sequential_visits.sql.
-- The trigger definition itself (AFTER UPDATE OF status) is unchanged.

CREATE OR REPLACE FUNCTION public.fn_amc_visit_completed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_completed  int;
  v_effective  int;
  v_status     text;
  v_expires_at timestamptz;
  v_new_status text;
  v_next_num   int;
BEGIN
  -- Count how many visits for this contract are now completed.
  -- (AFTER trigger: NEW is already in its new 'completed' state.)
  SELECT count(*) INTO v_completed
  FROM   public.bookings
  WHERE  amc_contract_id = NEW.amc_contract_id
    AND  status = 'completed';

  -- Fetch current contract state in one query.
  SELECT
    coalesce(num_visits, total_visits, 0),
    status,
    expires_at
  INTO v_effective, v_status, v_expires_at
  FROM public.amc_contracts
  WHERE id = NEW.amc_contract_id;

  -- ── Determine new status ────────────────────────────────────────────────────
  IF v_effective > 0 AND v_completed >= v_effective THEN
    -- All purchased visits are done. 'completed' takes precedence over
    -- everything, including expiry and cancellation_requested.
    v_new_status := 'completed';

  ELSIF v_status = 'cancellation_requested' THEN
    -- D3: Do not let a visit completion override cancellation_requested with
    -- 'active' or 'expired'. Admin must resolve the cancellation first.
    v_new_status := 'cancellation_requested';

  ELSIF v_expires_at IS NOT NULL AND v_expires_at < now() THEN
    -- Contract is past its expiry date. Lazily transition to 'expired'.
    -- The next-visit auto-creation block below is skipped for this path.
    v_new_status := 'expired';

  ELSE
    -- Normal active case with remaining visits.
    v_new_status := 'active';
  END IF;

  -- Persist counter and status.
  UPDATE public.amc_contracts
  SET
    visits_completed = v_completed,
    status           = v_new_status,
    updated_at       = now()
  WHERE id = NEW.amc_contract_id;

  -- ── Auto-create next visit booking ─────────────────────────────────────────
  -- Only when:
  --   a) The contract is still active (not expired, not cancellation_requested,
  --      not completed just now).
  --   b) Visits remain (v_effective = 0 means uncapped).
  --   c) No other non-terminal booking already exists for this contract
  --      (prevents duplicate creation if the customer races to checkout).
  IF v_new_status = 'active'
    AND (v_effective = 0 OR v_completed < v_effective)
    AND NOT EXISTS (
      SELECT 1
      FROM   public.bookings
      WHERE  amc_contract_id = NEW.amc_contract_id
        AND  id              <> NEW.id
        AND  status NOT IN ('completed', 'cancelled', 'rejected')
    )
  THEN
    v_next_num := v_completed + 1;

    INSERT INTO public.bookings (
      customer_id,
      service_id,
      status,
      subtotal,
      discount_amount,
      total_amount,
      address,
      latitude,
      longitude,
      payment_method,
      payment_status,
      is_amc,
      amc_contract_id,
      amc_plan_name,
      amc_recurrence_interval,
      amc_visit_number,
      completion_otp
    ) VALUES (
      NEW.customer_id,
      NEW.service_id,
      'pending',
      NEW.subtotal,
      0,
      NEW.subtotal,
      NEW.address,
      NEW.latitude,
      NEW.longitude,
      coalesce(NEW.payment_method, 'cash'),
      'pending',
      true,
      NEW.amc_contract_id,
      NEW.amc_plan_name,
      NEW.amc_recurrence_interval,
      v_next_num,
      lpad((floor(random() * 900000) + 100000)::bigint::text, 6, '0')
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger definition is unchanged from 20260730000007 — just re-create to bind
-- the new function body.
DROP TRIGGER IF EXISTS trg_amc_visit_completed ON public.bookings;

CREATE TRIGGER trg_amc_visit_completed
  AFTER UPDATE OF status ON public.bookings
  FOR EACH ROW
  WHEN (
    NEW.is_amc = true
    AND NEW.amc_contract_id IS NOT NULL
    AND NEW.status = 'completed'
    AND (OLD.status IS DISTINCT FROM 'completed')
  )
  EXECUTE FUNCTION public.fn_amc_visit_completed();
