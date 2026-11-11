-- Fix: car_wash mode with no slot config was returning unavailable.
-- Car Wash behaves like Instant — available 24/7 unless a slot config restricts it.

CREATE OR REPLACE FUNCTION check_instahelp_instant_availability(p_mode_id UUID)
RETURNS TABLE(is_available BOOLEAN, opens_in_minutes INTEGER)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_mode_type TEXT;
  v_config    RECORD;
  v_override  RECORD;
  v_now       TIME;
  v_today     DATE;
  v_dow       INTEGER;
  v_start     TIME;
  v_end       TIME;
BEGIN
  v_today := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_now   := (NOW() AT TIME ZONE 'Asia/Kolkata')::TIME;
  v_dow   := EXTRACT(DOW FROM v_today)::INTEGER;

  SELECT mode_type INTO v_mode_type
  FROM   instahelp_modes
  WHERE  id = p_mode_id AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::INTEGER;
    RETURN;
  END IF;

  SELECT * INTO v_config
  FROM   instahelp_slot_config
  WHERE  mode_id = p_mode_id AND is_active = TRUE;

  IF NOT FOUND THEN
    -- instant and car_wash with no slot config → available 24/7
    IF v_mode_type IN ('instant', 'car_wash') THEN
      RETURN QUERY SELECT TRUE, 0;
    ELSE
      RETURN QUERY SELECT FALSE, NULL::INTEGER;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO v_override
  FROM   instahelp_date_overrides
  WHERE  mode_id = p_mode_id
    AND  v_today BETWEEN start_date AND end_date
  ORDER  BY start_date DESC
  LIMIT  1;

  IF FOUND THEN
    IF NOT v_override.is_available THEN
      RETURN QUERY SELECT FALSE, NULL::INTEGER;
      RETURN;
    END IF;
    v_start := COALESCE(v_override.custom_start_time, v_config.start_time);
    v_end   := COALESCE(v_override.custom_end_time,   v_config.end_time);
  ELSE
    IF NOT (v_config.working_days @> to_jsonb(v_dow)) THEN
      RETURN QUERY SELECT FALSE, NULL::INTEGER;
      RETURN;
    END IF;
    v_start := v_config.start_time;
    v_end   := v_config.end_time;
  END IF;

  IF v_now >= v_start AND v_now < v_end THEN
    RETURN QUERY SELECT TRUE, 0;
  ELSIF v_now < v_start THEN
    RETURN QUERY SELECT FALSE,
      (EXTRACT(EPOCH FROM (v_start - v_now)) / 60)::INTEGER;
  ELSE
    RETURN QUERY SELECT FALSE, NULL::INTEGER;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION check_instahelp_instant_availability(UUID)
  TO anon, authenticated;
