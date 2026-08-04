-- ─────────────────────────────────────────────────────────────────────────────
-- Fix GPS Cancellation Audit Trigger & Bookings Cancellation Schema
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Ensure bookings table has cancellation tracking columns
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS cancelled_by         TEXT,
  ADD COLUMN IF NOT EXISTS cancellation_reason   TEXT,
  ADD COLUMN IF NOT EXISTS cancellation_remarks  TEXT;

-- 2. Update reusable audit function
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
  -- Fetch booking details
  SELECT vendor_id, customer_id, COALESCE(cancellation_reason, cancellation_remarks)
    INTO v_vendor_id, v_customer_id, v_reason
    FROM bookings
    WHERE id = p_booking_id;

  IF v_vendor_id IS NULL OR v_customer_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Run geofence validation
  SELECT * INTO v_geo
    FROM validate_vendor_geofence(p_booking_id);

  -- If vendor was inside geofence during cancellation, snapshot evidence into audit table
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

-- 3. Update trigger function to safely filter for customer vendor-related cancellations
CREATE OR REPLACE FUNCTION fn_tr_audit_customer_cancellation_gps()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_reason TEXT;
BEGIN
  -- Trigger only on cancellation transition for bookings with an assigned vendor
  -- and initiated by customer (or unspecified cancelled_by)
  IF NEW.status = 'cancelled' AND (OLD.status IS NULL OR OLD.status <> 'cancelled')
     AND NEW.vendor_id IS NOT NULL
     AND (NEW.cancelled_by IS NULL OR NEW.cancelled_by = 'customer') THEN

    v_reason := LOWER(COALESCE(NEW.cancellation_reason, NEW.cancellation_remarks, ''));

    -- Perform audit for unspecified reasons or vendor-related keywords
    IF v_reason = ''
       OR v_reason LIKE '%vendor%'
       OR v_reason LIKE '%delay%'
       OR v_reason LIKE '%arrive%'
       OR v_reason LIKE '%show%'
       OR v_reason LIKE '%late%'
       OR v_reason LIKE '%wait%'
       OR v_reason LIKE '%unreachable%'
       OR v_reason LIKE '%slow%' THEN

      PERFORM audit_customer_cancellation_gps(NEW.id);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 4. Re-attach trigger
DROP TRIGGER IF EXISTS tr_audit_customer_cancellation_gps ON bookings;

CREATE TRIGGER tr_audit_customer_cancellation_gps
  AFTER UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_tr_audit_customer_cancellation_gps();
