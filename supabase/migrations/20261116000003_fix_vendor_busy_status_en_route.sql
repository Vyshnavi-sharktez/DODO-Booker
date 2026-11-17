-- Migration: 20261116000003_fix_vendor_busy_status_en_route.sql
--
-- Migration 20260727000007 removed 'en_route' from the busy-status list with
-- the comment that it was a "legacy name never written by app code." That was
-- incorrect: the vendor "I'm On My Way" action transitions a booking to
-- en_route and has been in production use since the vendor app was shipped.
--
-- A vendor in en_route status has committed to a booking and is physically
-- traveling to the customer. They must be treated as busy for assignment purposes.

-- Two-part busy check:
--   Part 1 (date-scoped): vendor has an ACCEPTED booking on the same date.
--   Part 2 (status-scoped): vendor is currently en_route/in_progress/
--     awaiting_verification regardless of which date that booking was scheduled.
CREATE OR REPLACE FUNCTION get_vendor_busy_status(
  p_vendor_id    UUID,
  p_service_date TEXT,
  p_now_minutes  INT
)
RETURNS TABLE (
  is_busy            BOOLEAN,
  busy_until_minutes INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*)
  INTO   v_count
  FROM   bookings b
  WHERE  b.vendor_id = p_vendor_id
    AND (
      -- Committed to this specific date but not yet started
      (b.status = 'accepted' AND b.service_date::DATE = p_service_date::DATE)
      OR
      -- Physically active right now — date is irrelevant
      b.status IN ('en_route', 'in_progress', 'awaiting_verification')
    );

  IF v_count > 0 THEN
    RETURN QUERY SELECT TRUE, NULL::INT;
  ELSE
    RETURN QUERY SELECT FALSE, NULL::INT;
  END IF;
END;
$$;
