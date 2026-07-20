-- Fix: get_vendor_busy_status was comparing bookings.service_date (TIMESTAMPTZ)
-- to p_service_date (TEXT) directly, causing:
--   "operator does not exist: timestamp with time zone = text"
-- Fix: cast both sides to DATE so the types are compatible.

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
    WHERE  b.vendor_id             = p_vendor_id
      AND  b.service_date::DATE    = p_service_date::DATE
      AND  b.status                = ANY(v_busy_statuses)
      AND  b.scheduled_time        IS NOT NULL
  LOOP
    BEGIN
      v_normalized := REGEXP_REPLACE(
                        REGEXP_REPLACE(UPPER(v_row.scheduled_time), '\s+', '', 'g'),
                        '(AM|PM)$', ' \1'
                      );

      v_slot_minutes :=
          EXTRACT(HOUR   FROM TO_TIMESTAMP(v_normalized, 'HH12:MI AM')::TIME)::INT * 60
        + EXTRACT(MINUTE FROM TO_TIMESTAMP(v_normalized, 'HH12:MI AM')::TIME)::INT;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;
    END;

    v_busy_until := v_slot_minutes + v_row.duration;

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
