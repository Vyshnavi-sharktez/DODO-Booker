-- InstaHelp slot configuration per mode
CREATE TABLE IF NOT EXISTS instahelp_slot_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mode_id UUID NOT NULL UNIQUE REFERENCES instahelp_modes(id) ON DELETE CASCADE,
  working_days JSONB NOT NULL DEFAULT '[0,1,2,3,4,5,6]'::jsonb,
  start_time TIME NOT NULL DEFAULT '08:00',
  end_time TIME NOT NULL DEFAULT '20:00',
  slot_interval_minutes INTEGER NOT NULL DEFAULT 60 CHECK (slot_interval_minutes > 0),
  max_bookings_per_slot INTEGER NOT NULL DEFAULT 10 CHECK (max_bookings_per_slot > 0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Per-date overrides: mark a date unavailable or give it custom hours
CREATE TABLE IF NOT EXISTS instahelp_date_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mode_id UUID NOT NULL REFERENCES instahelp_modes(id) ON DELETE CASCADE,
  override_date DATE NOT NULL,
  is_available BOOLEAN NOT NULL DEFAULT FALSE,
  custom_start_time TIME,
  custom_end_time TIME,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(mode_id, override_date)
);

-- RLS
ALTER TABLE instahelp_slot_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE instahelp_date_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read instahelp_slot_config"
  ON instahelp_slot_config FOR SELECT TO anon, authenticated USING (TRUE);

CREATE POLICY "Admin manage instahelp_slot_config"
  ON instahelp_slot_config FOR ALL TO authenticated
  USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY "Public read instahelp_date_overrides"
  ON instahelp_date_overrides FOR SELECT TO anon, authenticated USING (TRUE);

CREATE POLICY "Admin manage instahelp_date_overrides"
  ON instahelp_date_overrides FOR ALL TO authenticated
  USING (TRUE) WITH CHECK (TRUE);

-- Seed default slot config for all existing modes
INSERT INTO instahelp_slot_config (mode_id, working_days, start_time, end_time, slot_interval_minutes, max_bookings_per_slot)
SELECT id, '[0,1,2,3,4,5,6]'::jsonb, '08:00', '20:00', 60, 10
FROM instahelp_modes
ON CONFLICT (mode_id) DO NOTHING;

-- RPC: return available time slots for a given mode + duration + date
-- Slots are per-duration so a 60-min and 120-min booking at the same time
-- each count against their own pool.
CREATE OR REPLACE FUNCTION get_instahelp_slots(
  p_mode_id UUID,
  p_duration_id UUID,
  p_date DATE
)
RETURNS TABLE(
  slot_time TEXT,
  is_available BOOLEAN,
  bookings_count INTEGER,
  max_bookings INTEGER
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config RECORD;
  v_override RECORD;
  v_start TIME;
  v_end TIME;
  v_interval INTEGER;
  v_max INTEGER;
  v_cur TIME;
  v_dow INTEGER;
  v_slot_str TEXT;
  v_count INTEGER;
BEGIN
  SELECT * INTO v_config
  FROM instahelp_slot_config
  WHERE mode_id = p_mode_id AND is_active = TRUE;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT * INTO v_override
  FROM instahelp_date_overrides
  WHERE mode_id = p_mode_id AND override_date = p_date;

  IF FOUND THEN
    IF NOT v_override.is_available THEN RETURN; END IF;
    v_start := COALESCE(v_override.custom_start_time, v_config.start_time);
    v_end   := COALESCE(v_override.custom_end_time,   v_config.end_time);
  ELSE
    v_dow := EXTRACT(DOW FROM p_date)::INTEGER;
    IF NOT (v_config.working_days @> to_jsonb(v_dow)) THEN RETURN; END IF;
    v_start := v_config.start_time;
    v_end   := v_config.end_time;
  END IF;

  v_interval := v_config.slot_interval_minutes;
  v_max      := v_config.max_bookings_per_slot;

  v_cur := v_start;
  WHILE v_cur < v_end LOOP
    v_slot_str := TO_CHAR((p_date + v_cur)::TIMESTAMP, 'FMHH12:MI AM');

    SELECT COUNT(*) INTO v_count
    FROM bookings b
    JOIN instahelp_bookings ib ON ib.booking_id = b.id
    WHERE ib.mode_id = p_mode_id
      AND ib.duration_id = p_duration_id
      AND b.service_date = p_date
      AND b.scheduled_time = v_slot_str
      AND b.status NOT IN ('cancelled', 'rejected');

    RETURN QUERY SELECT v_slot_str, (v_count < v_max), v_count::INTEGER, v_max;
    v_cur := v_cur + (v_interval || ' minutes')::INTERVAL;
  END LOOP;
END;
$$;

-- RPC: check if instant booking is available right now
CREATE OR REPLACE FUNCTION check_instahelp_instant_availability(p_mode_id UUID)
RETURNS TABLE(is_available BOOLEAN, opens_in_minutes INTEGER)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config RECORD;
  v_override RECORD;
  v_now TIME;
  v_today DATE;
  v_dow INTEGER;
  v_start TIME;
  v_end TIME;
BEGIN
  v_today := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_now   := (NOW() AT TIME ZONE 'Asia/Kolkata')::TIME;
  v_dow   := EXTRACT(DOW FROM v_today)::INTEGER;

  SELECT * INTO v_config
  FROM instahelp_slot_config
  WHERE mode_id = p_mode_id AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::INTEGER;
    RETURN;
  END IF;

  SELECT * INTO v_override
  FROM instahelp_date_overrides
  WHERE mode_id = p_mode_id AND override_date = v_today;

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
