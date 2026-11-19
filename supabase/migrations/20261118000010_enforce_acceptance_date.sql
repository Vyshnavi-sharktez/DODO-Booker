-- Migration: 20261118000010_enforce_acceptance_date.sql
--
-- Restrict vendor acceptance to the actual booking date.
-- A vendor assigned to a booking cannot accept it until service_date arrives
-- (evaluated in the configured timezone from the settings table).
--
-- Applies only to: assigned/pending → accepted transitions for external vendors.
-- Does not affect: rejection, en_route, in_progress, completed, or DODO Team flows.

CREATE OR REPLACE FUNCTION fn_enforce_acceptance_date()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tz    TEXT;
  v_today DATE;
BEGIN
  -- Only restrict the assigned/pending → accepted transition.
  IF NEW.status = 'accepted' AND OLD.status IN ('assigned', 'pending') THEN
    SELECT setting_value INTO v_tz
    FROM   settings
    WHERE  setting_key = 'timezone';

    v_tz    := COALESCE(v_tz, 'UTC');
    v_today := (NOW() AT TIME ZONE v_tz)::DATE;

    IF NEW.service_date::DATE > v_today THEN
      RAISE EXCEPTION
        'Booking cannot be accepted before the scheduled date (%). Today is %.',
        NEW.service_date::DATE, v_today
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_acceptance_date ON bookings;
CREATE TRIGGER trg_enforce_acceptance_date
  BEFORE UPDATE OF status ON bookings
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION fn_enforce_acceptance_date();
