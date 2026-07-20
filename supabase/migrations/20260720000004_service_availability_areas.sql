-- Service Availability Areas: platform-level serviceability zones.
-- Controls where DODO Booker currently offers services to customers.
-- Distinct from vendor_serving_areas (which controls individual vendor coverage).
--
-- Design:
-- • Named zones with lat/lng center + radius_km — same Haversine approach as
--   vendor_serving_areas; no vendor junction table (platform-wide setting).
-- • is_location_serviceable() RPC: returns TRUE when (p_lat, p_lng) falls inside
--   any active zone.  Returns TRUE when no active zones exist (opt-in feature —
--   zero config means no restriction).
-- • LEAST(1.0, …) guard inside acos() prevents NaN from floating-point rounding
--   when a point is exactly on the zone boundary.
-- • Overlapping zones are safe — EXISTS short-circuits on first match.
-- • Inactive zones are ignored by both the RPC and the admin active filter.

CREATE TABLE service_availability_areas (
  id         UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT            NOT NULL,
  city       TEXT            NOT NULL,
  latitude   NUMERIC(10, 7)  NOT NULL,
  longitude  NUMERIC(10, 7)  NOT NULL,
  radius_km  NUMERIC(6, 2)   NOT NULL DEFAULT 5.0,
  is_active  BOOLEAN         NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ     NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE INDEX idx_saa_active ON service_availability_areas (is_active)
  WHERE is_active = true;

ALTER TABLE service_availability_areas ENABLE ROW LEVEL SECURITY;

-- Public read (anon = customer app); authenticated write (admin panel).
CREATE POLICY "saa_anon_read"  ON service_availability_areas FOR SELECT TO anon         USING (true);
CREATE POLICY "saa_auth_read"  ON service_availability_areas FOR SELECT TO authenticated USING (true);
CREATE POLICY "saa_auth_write" ON service_availability_areas FOR ALL    TO authenticated USING (true) WITH CHECK (true);

-- ── Serviceability RPC ─────────────────────────────────────────────────────────
-- SECURITY DEFINER so the anon role can call it even though RLS is enabled.
-- Returns TRUE if (p_lat, p_lng) is within radius_km of any active zone center.
-- Edge cases handled:
--   • No active zones → TRUE  (opt-in; zero config = no restriction)
--   • Duplicate / overlapping zones → safe (EXISTS short-circuits)
--   • Boundary points where trig rounds above 1.0 → LEAST(1.0, …) prevents NaN
--   • NULL p_lat / p_lng → acos(NaN) = NaN; distance > radius_km → FALSE
--     (correctly blocks a booking with no coordinates when zones are configured)

CREATE OR REPLACE FUNCTION is_location_serviceable(
  p_lat NUMERIC,
  p_lng NUMERIC
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN NOT EXISTS (
      SELECT 1 FROM service_availability_areas WHERE is_active = true
    )
    THEN true  -- opt-in: no zones configured → all locations serviceable

    ELSE EXISTS (
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
    )
  END;
$$;
