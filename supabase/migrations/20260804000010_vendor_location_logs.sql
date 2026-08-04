-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 1: GPS Tracking Foundation — vendor_location_logs table & RPC
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS vendor_location_logs (
  id           UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id   UUID           NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  vendor_id    UUID           NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  latitude     NUMERIC(10, 7) NOT NULL,
  longitude    NUMERIC(10, 7) NOT NULL,
  accuracy     NUMERIC(8, 2),
  recorded_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- Performance Indexes
CREATE INDEX IF NOT EXISTS idx_vendor_location_logs_booking_id ON vendor_location_logs (booking_id);
CREATE INDEX IF NOT EXISTS idx_vendor_location_logs_vendor_id  ON vendor_location_logs (vendor_id);
CREATE INDEX IF NOT EXISTS idx_vendor_location_logs_recorded_at ON vendor_location_logs (recorded_at DESC);

-- Enable RLS
ALTER TABLE vendor_location_logs ENABLE ROW LEVEL SECURITY;

-- Admin & Service Role Policy: Full Access
CREATE POLICY "admin_service_role_all_vendor_location_logs"
  ON vendor_location_logs FOR ALL
  TO authenticated, service_role
  USING (true) WITH CHECK (true);

-- Authenticated Vendor Policy: Vendors can view/insert their own location records
CREATE POLICY "vendor_own_vendor_location_logs"
  ON vendor_location_logs FOR ALL
  TO authenticated
  USING (vendor_id = auth.uid()) WITH CHECK (vendor_id = auth.uid());

-- NO ANONYMOUS ACCESS: Direct anon access is strictly blocked.
-- Location Logging RPC with SECURITY DEFINER for secure location logging
CREATE OR REPLACE FUNCTION log_vendor_location(
  p_booking_id UUID,
  p_vendor_id  UUID,
  p_latitude   NUMERIC,
  p_longitude  NUMERIC,
  p_accuracy   NUMERIC DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_log_id UUID;
BEGIN
  IF p_booking_id IS NULL OR p_vendor_id IS NULL THEN
    RAISE EXCEPTION 'booking_id and vendor_id are required';
  END IF;

  -- Discard positions with accuracy > 100 meters
  IF p_accuracy IS NOT NULL AND p_accuracy > 100.0 THEN
    RETURN NULL;
  END IF;

  INSERT INTO vendor_location_logs (
    booking_id, vendor_id, latitude, longitude, accuracy, recorded_at
  ) VALUES (
    p_booking_id, p_vendor_id, p_latitude, p_longitude, p_accuracy, now()
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;
