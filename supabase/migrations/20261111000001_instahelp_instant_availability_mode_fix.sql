-- Fix: check_instahelp_instant_availability was treating a missing
-- instahelp_slot_config row as unavailable for ALL mode types.
--
-- Correct per-mode behaviour:
--   instant   — no slot config → available now (TRUE, 0); config present →
--               apply working-day / date-override / time-window checks as before.
--   car_wash  — slot config required; missing config → unavailable (FALSE, NULL).
--   scheduled — this RPC is not called for scheduled bookings, but if it ever
--               is, missing config → unavailable (FALSE, NULL).
--
-- All other logic (date overrides, working-day bitmap, time-window comparison,
-- opens_in_minutes calculation) is preserved exactly.

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

  -- Resolve mode type; mode must exist and be active.
  SELECT mode_type INTO v_mode_type
  FROM   instahelp_modes
  WHERE  id = p_mode_id AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::INTEGER;
    RETURN;
  END IF;

  -- Look for a slot-config row for this mode.
  SELECT * INTO v_config
  FROM   instahelp_slot_config
  WHERE  mode_id = p_mode_id AND is_active = TRUE;

  IF NOT FOUND THEN
    -- Instant without a slot config → available 24/7.
    -- Car Wash and Scheduled require an explicit config to be bookable.
    IF v_mode_type = 'instant' THEN
      RETURN QUERY SELECT TRUE, 0;
    ELSE
      RETURN QUERY SELECT FALSE, NULL::INTEGER;
    END IF;
    RETURN;
  END IF;

  -- ── Slot config exists: apply date-override then working-day / time checks ──

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
    -- No date override: check working-day bitmap.
    IF NOT (v_config.working_days @> to_jsonb(v_dow)) THEN
      RETURN QUERY SELECT FALSE, NULL::INTEGER;
      RETURN;
    END IF;
    v_start := v_config.start_time;
    v_end   := v_config.end_time;
  END IF;

  -- Time-window comparison.
  IF v_now >= v_start AND v_now < v_end THEN
    RETURN QUERY SELECT TRUE, 0;
  ELSIF v_now < v_start THEN
    RETURN QUERY SELECT FALSE,
      (EXTRACT(EPOCH FROM (v_start - v_now)) / 60)::INTEGER;
  ELSE
    -- Past closing time today.
    RETURN QUERY SELECT FALSE, NULL::INTEGER;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION check_instahelp_instant_availability(UUID)
  TO anon, authenticated;
