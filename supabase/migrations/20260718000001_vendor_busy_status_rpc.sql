-- RPC: get_vendor_busy_status
--
-- Determines whether a vendor is currently busy based on their active bookings
-- for a given service date, using each booked service's estimated_duration to
-- compute the actual end time.
--
-- Why SECURITY DEFINER:
--   The bookings table is RLS-protected. Customers are permitted to read only
--   their own booking rows. Querying by vendor_id to check another customer's
--   booking would return 0 rows under customer RLS, making the check useless.
--   This function runs as the DB owner, reads the bookings it needs, and returns
--   only a derived availability result — never exposing booking details.
--
-- Parameters:
--   p_vendor_id    — UUID of the preferred vendor to check
--   p_service_date — 'YYYY-MM-DD' date string; cast to DATE for comparison
--                    against bookings.service_date (TIMESTAMPTZ) via ::DATE
--   p_now_minutes  — minutes since midnight in the caller's local timezone
--
-- Returns one row:
--   is_busy            — true if vendor has an active booking whose service
--                        window has not ended (covers both in-progress and
--                        upcoming committed bookings)
--   busy_until_minutes — end of the latest active window (slot + duration),
--                        null when is_busy is false

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
  v_busy_statuses  TEXT[] := ARRAY[
    'assigned', 'accepted', 'en_route', 'started', 'in_progress', 'awaiting_verification'
  ];
  v_row            RECORD;
  v_normalized     TEXT;
  v_slot_minutes   INT;
  v_busy_until     INT;
  v_max_busy_until INT := 0;
BEGIN
  FOR v_row IN
    SELECT
      b.scheduled_time,
      COALESCE(cn.estimated_duration, 60) AS duration
    FROM   bookings b
    LEFT   JOIN catalog_nodes cn ON cn.id = b.service_id
    WHERE  b.vendor_id        = p_vendor_id
      AND  b.service_date::DATE = p_service_date::DATE
      AND  b.status           = ANY(v_busy_statuses)
      AND  b.scheduled_time   IS NOT NULL
  LOOP
    BEGIN
      -- Normalize scheduled_time to 'H:MM AM/PM' form before parsing.
      -- Handles all stored variants: '6:00PM', '10:06 PM', '01:44 PM',
      -- lowercase, and extra surrounding whitespace.
      v_normalized := REGEXP_REPLACE(
                        REGEXP_REPLACE(UPPER(v_row.scheduled_time), '\s+', '', 'g'),
                        '(AM|PM)$', ' \1'
                      );

      v_slot_minutes :=
          EXTRACT(HOUR   FROM TO_TIMESTAMP(v_normalized, 'HH12:MI AM')::TIME)::INT * 60
        + EXTRACT(MINUTE FROM TO_TIMESTAMP(v_normalized, 'HH12:MI AM')::TIME)::INT;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE; -- skip any row with an unparseable scheduled_time
    END;

    v_busy_until := v_slot_minutes + v_row.duration;

    -- Vendor is busy while their service window has not ended.
    -- This covers both bookings that have already started (slot in the past)
    -- and upcoming committed bookings (slot in the future) — in both cases
    -- the vendor is unavailable until the job completes.
    IF p_now_minutes < v_busy_until AND v_busy_until > v_max_busy_until THEN
      v_max_busy_until := v_busy_until;
    END IF;
  END LOOP;

  IF v_max_busy_until > 0 THEN
    RETURN QUERY SELECT TRUE, v_max_busy_until;
  ELSE
    RETURN QUERY SELECT FALSE, NULL::INT;
  END IF;
END;
$$;
