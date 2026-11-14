-- Fix: get_instahelp_slots was returning empty when no instahelp_slot_config exists.
-- Global config is now OPTIONAL — used only for working_days check.
-- Duration's own slot times are always used for start/end/interval/max.
-- If no global config: all days allowed, duration times apply directly.
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
  v_has_config BOOLEAN := FALSE;
  v_start    TIME;
  v_end      TIME;
  v_interval INTEGER;
  v_max      INTEGER;
  v_cur      TIME;
  v_dow      INTEGER;
  v_slot_str TEXT;
  v_count    INTEGER;
BEGIN
  -- Duration config is required
  SELECT slot_start_time, slot_end_time, slot_interval_minutes, max_bookings_per_slot
  INTO v_duration
  FROM instahelp_durations
  WHERE id = p_duration_id AND is_active = TRUE;

  IF NOT FOUND THEN RETURN; END IF;

  -- Global config is optional — only used for working_days
  SELECT * INTO v_config
  FROM instahelp_slot_config
  WHERE mode_id = p_mode_id AND is_active = TRUE;
  v_has_config := FOUND;

  -- Date override takes highest priority
  SELECT * INTO v_override
  FROM instahelp_date_overrides
  WHERE mode_id = p_mode_id AND override_date = p_date;

  IF FOUND THEN
    IF NOT v_override.is_available THEN RETURN; END IF;
    v_start := COALESCE(v_override.custom_start_time, v_duration.slot_start_time);
    v_end   := COALESCE(v_override.custom_end_time,   v_duration.slot_end_time);
  ELSE
    -- Check working days only if global config exists
    IF v_has_config THEN
      v_dow := EXTRACT(DOW FROM p_date)::INTEGER;
      IF NOT (v_config.working_days @> to_jsonb(v_dow)) THEN RETURN; END IF;
    END IF;
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
    WHERE ib.mode_id      = p_mode_id
      AND ib.duration_id  = p_duration_id
      AND b.service_date  = p_date
      AND b.scheduled_time = v_slot_str
      AND b.status NOT IN ('cancelled', 'rejected');

    RETURN QUERY SELECT v_slot_str, (v_count < v_max), v_count::INTEGER, v_max;
    v_cur := v_cur + (v_interval || ' minutes')::INTERVAL;
  END LOOP;
END;
$$;
