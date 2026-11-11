-- Convert instahelp_date_overrides from single date to date range

ALTER TABLE instahelp_date_overrides
  ADD COLUMN IF NOT EXISTS start_date DATE,
  ADD COLUMN IF NOT EXISTS end_date DATE;

-- Migrate existing single-date rows
UPDATE instahelp_date_overrides
SET start_date = override_date,
    end_date   = override_date
WHERE start_date IS NULL;

ALTER TABLE instahelp_date_overrides
  ALTER COLUMN start_date SET NOT NULL,
  ALTER COLUMN end_date   SET NOT NULL;

-- Drop old unique constraint and column
ALTER TABLE instahelp_date_overrides
  DROP CONSTRAINT IF EXISTS instahelp_date_overrides_mode_id_override_date_key;

ALTER TABLE instahelp_date_overrides
  DROP COLUMN IF EXISTS override_date;

-- Update get_instahelp_slots to match date against range
CREATE OR REPLACE FUNCTION get_instahelp_slots(
  p_mode_id    UUID,
  p_duration_id UUID,
  p_date       DATE
)
RETURNS TABLE(
  slot_time      TEXT,
  is_available   BOOLEAN,
  bookings_count INTEGER,
  max_bookings   INTEGER
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config   RECORD;
  v_duration RECORD;
  v_override RECORD;
  v_start    TIME;
  v_end      TIME;
  v_interval INTEGER;
  v_max      INTEGER;
  v_cur      TIME;
  v_dow      INTEGER;
  v_slot_str TEXT;
  v_count    INTEGER;
BEGIN
  SELECT * INTO v_config
  FROM instahelp_slot_config
  WHERE mode_id = p_mode_id AND is_active = TRUE;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT slot_start_time, slot_end_time, slot_interval_minutes, max_bookings_per_slot
  INTO v_duration
  FROM instahelp_durations
  WHERE id = p_duration_id AND is_active = TRUE;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT * INTO v_override
  FROM instahelp_date_overrides
  WHERE mode_id = p_mode_id
    AND p_date BETWEEN start_date AND end_date
  ORDER BY start_date DESC
  LIMIT 1;

  IF FOUND THEN
    IF NOT v_override.is_available THEN RETURN; END IF;
    v_start := COALESCE(v_override.custom_start_time, v_duration.slot_start_time);
    v_end   := COALESCE(v_override.custom_end_time,   v_duration.slot_end_time);
  ELSE
    v_dow := EXTRACT(DOW FROM p_date)::INTEGER;
    IF NOT (v_config.working_days @> to_jsonb(v_dow)) THEN RETURN; END IF;
    v_start := v_duration.slot_start_time;
    v_end   := v_duration.slot_end_time;
  END IF;

  v_interval := v_duration.slot_interval_minutes;
  v_max      := v_duration.max_bookings_per_slot;

  v_cur := v_start;
  WHILE v_cur < v_end LOOP
    v_slot_str := TO_CHAR((p_date + v_cur)::TIMESTAMP, 'FMHH12:MI AM');

    SELECT COUNT(*) INTO v_count
    FROM bookings b
    JOIN instahelp_bookings ib ON ib.booking_id = b.id
    WHERE ib.mode_id     = p_mode_id
      AND ib.duration_id = p_duration_id
      AND b.service_date = p_date
      AND b.scheduled_time = v_slot_str
      AND b.status NOT IN ('cancelled', 'rejected');

    RETURN QUERY SELECT v_slot_str, (v_count < v_max), v_count::INTEGER, v_max;
    v_cur := v_cur + (v_interval || ' minutes')::INTERVAL;
  END LOOP;
END;
$$;

-- Update check_instahelp_instant_availability to match range
CREATE OR REPLACE FUNCTION check_instahelp_instant_availability(p_mode_id UUID)
RETURNS TABLE(is_available BOOLEAN, opens_in_minutes INTEGER)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config   RECORD;
  v_override RECORD;
  v_now      TIME;
  v_today    DATE;
  v_dow      INTEGER;
  v_start    TIME;
  v_end      TIME;
BEGIN
  v_today := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_now   := (NOW() AT TIME ZONE 'Asia/Kolkata')::TIME;
  v_dow   := EXTRACT(DOW FROM v_today)::INTEGER;

  SELECT * INTO v_config
  FROM instahelp_slot_config
  WHERE mode_id = p_mode_id AND is_active = TRUE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::INTEGER; RETURN;
  END IF;

  SELECT * INTO v_override
  FROM instahelp_date_overrides
  WHERE mode_id = p_mode_id
    AND v_today BETWEEN start_date AND end_date
  ORDER BY start_date DESC
  LIMIT 1;

  IF FOUND THEN
    IF NOT v_override.is_available THEN
      RETURN QUERY SELECT FALSE, NULL::INTEGER; RETURN;
    END IF;
    v_start := COALESCE(v_override.custom_start_time, v_config.start_time);
    v_end   := COALESCE(v_override.custom_end_time,   v_config.end_time);
  ELSE
    IF NOT (v_config.working_days @> to_jsonb(v_dow)) THEN
      RETURN QUERY SELECT FALSE, NULL::INTEGER; RETURN;
    END IF;
    v_start := v_config.start_time;
    v_end   := v_config.end_time;
  END IF;

  IF v_now >= v_start AND v_now < v_end THEN
    RETURN QUERY SELECT TRUE, 0;
  ELSIF v_now < v_start THEN
    RETURN QUERY SELECT FALSE, (EXTRACT(EPOCH FROM (v_start - v_now)) / 60)::INTEGER;
  ELSE
    RETURN QUERY SELECT FALSE, NULL::INTEGER;
  END IF;
END;
$$;
