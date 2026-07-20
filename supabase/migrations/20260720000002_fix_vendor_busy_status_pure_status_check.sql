-- Rewrite get_vendor_busy_status to be purely status-based.
--
-- The previous version used time-based logic (slot_minutes + duration > p_now_minutes),
-- which (a) included 'assigned' as a busy status — wrong per business rules, since
-- an assigned booking means admin confirmed but vendor has not yet accepted, so the
-- vendor is not actively working and other customers should still be able to book them,
-- and (b) could miss active bookings when p_now_minutes was larger than the slot end.
--
-- New logic: vendor is BUSY if they have ANY booking in an active (post-accept) status
-- on the given date, regardless of scheduled time or duration. Purely status-based.
--
-- Busy statuses: accepted, en_route, started, in_progress, awaiting_verification
-- NOT busy: assigned (admin-confirmed, vendor not yet accepted — vendor still available
--           to other customers until they actively accept a job), completed, cancelled, rejected
--
-- p_now_minutes is retained in the function signature for backwards compatibility
-- with existing callers; it is no longer used in the logic.

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
    'accepted', 'en_route', 'started', 'in_progress', 'awaiting_verification'
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
