-- Migration: 20261118000012_fix_acceptance_date_restriction.sql
--
-- Correction: the date restriction applies to "I'm On My Way" (accepted → en_route),
-- not to Accept (assigned → accepted). Vendors can accept in advance to confirm
-- availability; they just cannot mark themselves en route until the booking date.

CREATE OR REPLACE FUNCTION fn_enforce_acceptance_date()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tz    TEXT;
  v_today DATE;
BEGIN
  -- Block en_route until the booking date arrives.
  IF NEW.status = 'en_route' AND OLD.status = 'accepted' THEN
    SELECT setting_value INTO v_tz
    FROM   settings
    WHERE  setting_key = 'timezone';

    v_tz    := COALESCE(v_tz, 'UTC');
    v_today := (NOW() AT TIME ZONE v_tz)::DATE;

    IF NEW.service_date::DATE > v_today THEN
      RAISE EXCEPTION
        'Cannot mark en route before the scheduled date (%). Today is %.',
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
