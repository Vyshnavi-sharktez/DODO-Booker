-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 2: GPS Geofence Validation — Haversine function & validate_vendor_geofence RPC
-- ─────────────────────────────────────────────────────────────────────────────

-- Helper function to calculate Haversine distance in meters between two lat/lng coordinates
CREATE OR REPLACE FUNCTION haversine_distance_meters(
  lat1 NUMERIC, lng1 NUMERIC,
  lat2 NUMERIC, lng2 NUMERIC
) RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
  r CONSTANT NUMERIC := 6371000.0; -- Earth radius in meters
  dlat NUMERIC;
  dlng NUMERIC;
  a NUMERIC;
BEGIN
  IF lat1 IS NULL OR lng1 IS NULL OR lat2 IS NULL OR lng2 IS NULL THEN
    RETURN NULL;
  END IF;

  dlat := radians(lat2 - lat1);
  dlng := radians(lng2 - lng1);

  a := power(sin(dlat / 2.0), 2) +
       cos(radians(lat1)) * cos(radians(lat2)) *
       power(sin(dlng / 2.0), 2);

  RETURN r * 2.0 * asin(sqrt(a));
END;
$$;

-- Reusable RPC: Validates whether vendor entered geofence during booking
CREATE OR REPLACE FUNCTION validate_vendor_geofence(
  p_booking_id UUID,
  p_geofence_radius_meters NUMERIC DEFAULT NULL
) RETURNS TABLE (
  booking_id               UUID,
  booking_latitude         NUMERIC,
  booking_longitude        NUMERIC,
  min_distance_meters      NUMERIC,
  is_inside_geofence       BOOLEAN,
  geofence_radius_meters   NUMERIC,
  nearest_location_log_id  UUID,
  nearest_latitude         NUMERIC,
  nearest_longitude        NUMERIC,
  nearest_accuracy         NUMERIC,
  nearest_recorded_at      TIMESTAMPTZ,
  total_locations_analyzed INT
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_b_lat     NUMERIC;
  v_b_lng     NUMERIC;
  v_radius    NUMERIC;
  v_total     INT := 0;
  v_min_dist  NUMERIC := NULL;
  v_inside    BOOLEAN := FALSE;
  v_log_id    UUID := NULL;
  v_n_lat     NUMERIC := NULL;
  v_n_lng     NUMERIC := NULL;
  v_n_acc     NUMERIC := NULL;
  v_n_time    TIMESTAMPTZ := NULL;
BEGIN
  -- 1. Fetch booking coordinates
  SELECT latitude, longitude INTO v_b_lat, v_b_lng
  FROM bookings
  WHERE id = p_booking_id;

  -- 2. Determine geofence radius (setting fallback to 100 meters using setting_key / setting_value)
  IF p_geofence_radius_meters IS NOT NULL AND p_geofence_radius_meters > 0 THEN
    v_radius := p_geofence_radius_meters;
  ELSE
    SELECT COALESCE(setting_value::NUMERIC, 100.0) INTO v_radius
    FROM settings
    WHERE setting_key = 'gps_geofence_radius_meters';
    
    IF v_radius IS NULL OR v_radius <= 0 THEN
      v_radius := 100.0;
    END IF;
  END IF;

  -- 3. If booking coordinates missing, return default response without error
  IF v_b_lat IS NULL OR v_b_lng IS NULL THEN
    RETURN QUERY SELECT
      p_booking_id,
      v_b_lat,
      v_b_lng,
      NULL::NUMERIC,
      FALSE,
      v_radius,
      NULL::UUID,
      NULL::NUMERIC,
      NULL::NUMERIC,
      NULL::NUMERIC,
      NULL::TIMESTAMPTZ,
      0;
    RETURN;
  END IF;

  -- 4. Count total location logs for booking
  SELECT COUNT(*)::INT INTO v_total
  FROM vendor_location_logs
  WHERE vendor_location_logs.booking_id = p_booking_id;

  -- 5. If no location logs exist, return graceful empty result
  IF v_total = 0 THEN
    RETURN QUERY SELECT
      p_booking_id,
      v_b_lat,
      v_b_lng,
      NULL::NUMERIC,
      FALSE,
      v_radius,
      NULL::UUID,
      NULL::NUMERIC,
      NULL::NUMERIC,
      NULL::NUMERIC,
      NULL::TIMESTAMPTZ,
      0;
    RETURN;
  END IF;

  -- 6. Find nearest recorded location log
  SELECT
    l.id,
    l.latitude,
    l.longitude,
    l.accuracy,
    l.recorded_at,
    haversine_distance_meters(v_b_lat, v_b_lng, l.latitude, l.longitude) AS dist
  INTO v_log_id, v_n_lat, v_n_lng, v_n_acc, v_n_time, v_min_dist
  FROM vendor_location_logs l
  WHERE l.booking_id = p_booking_id
  ORDER BY haversine_distance_meters(v_b_lat, v_b_lng, l.latitude, l.longitude) ASC, l.recorded_at DESC
  LIMIT 1;

  -- 7. Check inside geofence condition
  IF v_min_dist IS NOT NULL AND v_min_dist <= v_radius THEN
    v_inside := TRUE;
  ELSE
    v_inside := FALSE;
  END IF;

  RETURN QUERY SELECT
    p_booking_id,
    v_b_lat,
    v_b_lng,
    v_min_dist,
    v_inside,
    v_radius,
    v_log_id,
    v_n_lat,
    v_n_lng,
    v_n_acc,
    v_n_time,
    v_total;
END;
$$;
