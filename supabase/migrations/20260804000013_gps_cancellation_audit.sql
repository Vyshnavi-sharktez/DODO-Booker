-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 3: GPS Cancellation Audit — Table, backend audit function & trigger
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS gps_cancellation_audits (
  id                       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id               UUID         NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  vendor_id                UUID         NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  customer_id              UUID         NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  nearest_location_log_id  UUID         REFERENCES vendor_location_logs(id) ON DELETE SET NULL,
  min_distance_meters      NUMERIC      NOT NULL,
  geofence_radius_meters   NUMERIC      NOT NULL,
  booking_latitude         NUMERIC      NOT NULL,
  booking_longitude        NUMERIC      NOT NULL,
  nearest_latitude         NUMERIC      NOT NULL,
  nearest_longitude        NUMERIC      NOT NULL,
  nearest_accuracy         NUMERIC,
  nearest_recorded_at      TIMESTAMPTZ  NOT NULL,
  cancellation_reason      TEXT,
  audit_status             TEXT         NOT NULL DEFAULT 'potential_false_cancellation'
                           CHECK (audit_status IN ('pending_review', 'potential_false_cancellation', 'verified_false_cancellation', 'verified_valid_cancellation', 'dismissed')),
  audited_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Performance Indexes
CREATE INDEX IF NOT EXISTS idx_gps_cancellation_audits_booking_id  ON gps_cancellation_audits (booking_id);
CREATE INDEX IF NOT EXISTS idx_gps_cancellation_audits_vendor_id   ON gps_cancellation_audits (vendor_id);
CREATE INDEX IF NOT EXISTS idx_gps_cancellation_audits_customer_id ON gps_cancellation_audits (customer_id);
CREATE INDEX IF NOT EXISTS idx_gps_cancellation_audits_status      ON gps_cancellation_audits (audit_status);

-- Enable RLS
ALTER TABLE gps_cancellation_audits ENABLE ROW LEVEL SECURITY;

-- Admin & Service Role Policy
CREATE POLICY "admin_service_role_all_gps_cancellation_audits"
  ON gps_cancellation_audits FOR ALL
  TO authenticated, service_role
  USING (true) WITH CHECK (true);

-- Reusable Backend Service: Audits customer cancellation against GPS geofence validation
CREATE OR REPLACE FUNCTION audit_customer_cancellation_gps(
  p_booking_id UUID
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_vendor_id   UUID;
  v_customer_id UUID;
  v_reason      TEXT;
  v_geo         RECORD;
  v_audit_id    UUID;
BEGIN
  -- 1. Fetch booking details
  SELECT vendor_id, customer_id, COALESCE(cancellation_reason, cancellation_remarks)
    INTO v_vendor_id, v_customer_id, v_reason
    FROM bookings
    WHERE id = p_booking_id;

  IF v_vendor_id IS NULL OR v_customer_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- 2. Run geofence validation
  SELECT * INTO v_geo
    FROM validate_vendor_geofence(p_booking_id);

  -- 3. If vendor was inside geofence during cancellation, snapshot evidence into audit table
  IF v_geo.is_inside_geofence IS TRUE AND v_geo.min_distance_meters IS NOT NULL THEN
    INSERT INTO gps_cancellation_audits (
      booking_id,
      vendor_id,
      customer_id,
      nearest_location_log_id,
      min_distance_meters,
      geofence_radius_meters,
      booking_latitude,
      booking_longitude,
      nearest_latitude,
      nearest_longitude,
      nearest_accuracy,
      nearest_recorded_at,
      cancellation_reason,
      audit_status,
      audited_at
    ) VALUES (
      p_booking_id,
      v_vendor_id,
      v_customer_id,
      v_geo.nearest_location_log_id,
      v_geo.min_distance_meters,
      v_geo.geofence_radius_meters,
      v_geo.booking_latitude,
      v_geo.booking_longitude,
      v_geo.nearest_latitude,
      v_geo.nearest_longitude,
      v_geo.nearest_accuracy,
      v_geo.nearest_recorded_at,
      v_reason,
      'potential_false_cancellation',
      now()
    )
    RETURNING id INTO v_audit_id;

    RETURN v_audit_id;
  END IF;

  RETURN NULL;
END;
$$;

-- Trigger Function: Fires automatically when a booking status changes to 'cancelled' by customer
CREATE OR REPLACE FUNCTION fn_tr_audit_customer_cancellation_gps()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  -- Trigger on cancellation transition by customer with assigned vendor
  IF NEW.status = 'cancelled' AND (OLD.status IS NULL OR OLD.status <> 'cancelled')
     AND (NEW.cancelled_by IS NULL OR NEW.cancelled_by = 'customer')
     AND NEW.vendor_id IS NOT NULL THEN

    -- Audit via backend service (runs asynchronously, non-blocking)
    PERFORM audit_customer_cancellation_gps(NEW.id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_audit_customer_cancellation_gps ON bookings;

CREATE TRIGGER tr_audit_customer_cancellation_gps
  AFTER UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_tr_audit_customer_cancellation_gps();
