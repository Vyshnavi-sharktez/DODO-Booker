-- Atomically creates a vendor settlement batch covering multiple bookings.
--
-- Validations (all-or-nothing — any failure rolls back the entire call):
--   1. p_bookings must be non-empty.
--   2. Every booking_id must belong to p_vendor_id and have status = 'completed'.
--   3. No booking_id may already appear in vendor_settlement_bookings.
--
-- On success:
--   • Inserts one row into vendor_settlements (the batch header).
--   • Inserts one row per booking into vendor_settlement_bookings, storing
--     the caller-supplied snapshots (booking_gross, commission_amount, net_vendor_amount).
--   • Returns the new vendor_settlements.id.
--
-- The snapshot values are computed by the Flutter client using
-- resolve_catalog_module_config at the moment the admin opens the settle dialog.
-- Storing them here makes historical settled amounts immutable.

CREATE OR REPLACE FUNCTION create_vendor_settlement_batch(
  p_vendor_id        UUID,
  p_vendor_name      TEXT,
  p_settled_by       TEXT,
  p_payment_method   TEXT,
  p_reference_number TEXT,
  p_notes            TEXT,
  p_bookings         JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_settlement_id  UUID;
  v_total_amount   NUMERIC(12,2) := 0;
  v_booking        JSONB;
  v_booking_id     UUID;
  v_count          INT;
BEGIN
  IF p_bookings IS NULL OR jsonb_array_length(p_bookings) = 0 THEN
    RAISE EXCEPTION 'No bookings selected for settlement';
  END IF;

  -- Validate every booking before inserting anything.
  FOR v_booking IN SELECT value FROM jsonb_array_elements(p_bookings)
  LOOP
    v_booking_id := (v_booking->>'booking_id')::UUID;

    SELECT COUNT(*) INTO v_count
    FROM   bookings
    WHERE  id        = v_booking_id
      AND  vendor_id = p_vendor_id
      AND  status    = 'completed';

    IF v_count = 0 THEN
      RAISE EXCEPTION 'Booking % is not a completed booking for vendor %',
                      v_booking_id, p_vendor_id;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM   vendor_settlement_bookings
    WHERE  booking_id = v_booking_id;

    IF v_count > 0 THEN
      RAISE EXCEPTION 'Booking % has already been settled', v_booking_id;
    END IF;

    v_total_amount := v_total_amount + (v_booking->>'net_vendor_amount')::NUMERIC;
  END LOOP;

  -- Insert the settlement header.
  INSERT INTO vendor_settlements (
    vendor_id, vendor_name, amount, completed_jobs_count,
    payment_method, reference_number, notes, settled_by, settled_at
  ) VALUES (
    p_vendor_id,
    p_vendor_name,
    v_total_amount,
    jsonb_array_length(p_bookings),
    NULLIF(p_payment_method, ''),
    NULLIF(p_reference_number, ''),
    NULLIF(p_notes, ''),
    p_settled_by,
    now()
  )
  RETURNING id INTO v_settlement_id;

  -- Insert junction rows with immutable snapshots.
  FOR v_booking IN SELECT value FROM jsonb_array_elements(p_bookings)
  LOOP
    INSERT INTO vendor_settlement_bookings (
      settlement_id, booking_id,
      booking_gross, commission_amount, net_vendor_amount
    ) VALUES (
      v_settlement_id,
      (v_booking->>'booking_id')::UUID,
      (v_booking->>'booking_gross')::NUMERIC,
      (v_booking->>'commission_amount')::NUMERIC,
      (v_booking->>'net_vendor_amount')::NUMERIC
    );
  END LOOP;

  RETURN v_settlement_id;
END;
$$;
