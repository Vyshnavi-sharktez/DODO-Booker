-- ── AMC Assign-path UPDATE Guard ──────────────────────────────────────────────
--
-- Defense-in-depth for the "Assign Next" UPDATE path. The BEFORE INSERT trigger
-- (trg_check_amc_bookable, migration 20260911000004) only fires on INSERT, so a
-- direct UPDATE of an existing pending booking to 'assigned', 'accepted', or
-- 'in_progress' bypasses it entirely. This trigger closes that gap.
--
-- Fires only when ALL of the following are true:
--   1. The booking is an AMC booking (is_amc = true, amc_contract_id NOT NULL).
--   2. The status is moving FROM 'pending' (unscheduled placeholder) INTO an
--      active assignment state ('assigned', 'accepted', 'in_progress').
--   3. The AMC contract is not bookable (expired, inactive, or invalid).
--
-- Bookings that are already assigned / accepted continue through their lifecycle
-- (assigned → in_progress → completed) freely, even after contract expiry.
-- This preserves the locked business rule: existing confirmed bookings remain
-- valid after expiry and can still be completed.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_check_amc_assign_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.amc_contract_is_bookable(NEW.amc_contract_id) THEN
    RAISE EXCEPTION
      'amc_contract_not_bookable: AMC contract % is expired, inactive, or invalid',
      NEW.amc_contract_id
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_amc_assign_update ON public.bookings;

CREATE TRIGGER trg_check_amc_assign_update
  BEFORE UPDATE OF status ON public.bookings
  FOR EACH ROW
  WHEN (
    NEW.is_amc = true
    AND NEW.amc_contract_id IS NOT NULL
    AND OLD.status = 'pending'
    AND NEW.status IN ('assigned', 'accepted', 'in_progress')
  )
  EXECUTE FUNCTION public.fn_check_amc_assign_update();
