-- Global toggle for service area restrictions.
-- When disabled (the default), is_location_serviceable() returns TRUE for all
-- coordinates and _handleMissingCoordinates on the customer app bypasses zone
-- checks.  Existing service_availability_areas records are never touched.

-- 1. Seed the default setting (off — same runtime behaviour as before)
INSERT INTO settings (setting_key, setting_value)
VALUES ('service_area_restrictions_enabled', 'false')
ON CONFLICT (setting_key) DO NOTHING;

-- 2. Lightweight helper callable by anon so the customer app can query the
--    toggle without needing direct settings table access.
CREATE OR REPLACE FUNCTION public.is_service_area_restrictions_enabled()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT setting_value = 'true'
     FROM   settings
     WHERE  setting_key = 'service_area_restrictions_enabled'),
    false
  );
$$;

REVOKE ALL ON FUNCTION public.is_service_area_restrictions_enabled() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_service_area_restrictions_enabled() TO anon, authenticated;

-- 3. Replace is_location_serviceable to honour the global toggle.
--    When the toggle is OFF, returns TRUE immediately without reading any zones.
--    When ON, preserves the original opt-in + Haversine logic exactly.
CREATE OR REPLACE FUNCTION public.is_location_serviceable(
  p_lat NUMERIC,
  p_lng NUMERIC
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled BOOLEAN;
BEGIN
  SELECT COALESCE(setting_value = 'true', false)
  INTO   v_enabled
  FROM   settings
  WHERE  setting_key = 'service_area_restrictions_enabled';

  -- Global toggle off → all locations serviceable; skip zone check entirely.
  IF NOT COALESCE(v_enabled, false) THEN
    RETURN true;
  END IF;

  -- Original opt-in: no active zones configured → all locations serviceable.
  IF NOT EXISTS (SELECT 1 FROM service_availability_areas WHERE is_active = true) THEN
    RETURN true;
  END IF;

  -- Haversine distance check (formula identical to the original sql-language version).
  RETURN EXISTS (
    SELECT 1
    FROM   service_availability_areas
    WHERE  is_active = true
      AND  (
             6371.0 * acos(
               LEAST(1.0,
                 cos(radians(p_lat::FLOAT)) * cos(radians(latitude::FLOAT))
                 * cos(radians(longitude::FLOAT) - radians(p_lng::FLOAT))
                 + sin(radians(p_lat::FLOAT)) * sin(radians(latitude::FLOAT))
               )
             )
           ) <= radius_km
  );
END;
$$;
