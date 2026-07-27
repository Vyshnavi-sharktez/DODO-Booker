-- Align get_vendor_busy_status with the canonical busy-status definition.
--
-- Previous version (20260720000002) included 'en_route' and 'started', which
-- are legacy names that no app code has ever written to the bookings table.
-- Keeping them is harmless but misleading, so they are removed here.
--
-- Canonical busy statuses (vendor has committed to a job):
--   accepted              — vendor accepted the booking
--   in_progress           — service is underway
--   awaiting_verification — service done, waiting for customer OTP
--
-- NOT busy:
--   assigned              — admin offered the booking; vendor has not accepted,
--                           so they are still free to take other assignments
--   pending, completed, rejected, cancelled, assigned_to_dodo_team — not active
--
-- p_now_minutes is retained for backwards compatibility with existing callers;
-- it is not used in the logic.

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
  v_busy_statuses TEXT[] := ARRAY[
    'accepted', 'in_progress', 'awaiting_verification'
  ];
  v_count INT;
BEGIN
  SELECT COUNT(*)
  INTO   v_count
  FROM   bookings b
  WHERE  b.vendor_id          = p_vendor_id
    AND  b.service_date::DATE = p_service_date::DATE
    AND  b.status             = ANY(v_busy_statuses);

  IF v_count > 0 THEN
    RETURN QUERY SELECT TRUE, NULL::INT;
  ELSE
    RETURN QUERY SELECT FALSE, NULL::INT;
  END IF;
END;
$$;
