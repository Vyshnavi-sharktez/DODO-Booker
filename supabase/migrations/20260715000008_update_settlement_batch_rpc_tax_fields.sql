-- Updates create_vendor_settlement_batch to snapshot the three new tax-breakdown
-- columns added in migration 20260715000007.
--
-- The caller (Flutter client) passes subtotal_before_tax, tax_amount, and
-- commission_base per booking inside p_bookings JSONB.  If a key is absent the
-- column stores NULL (backward-compatible with any caller that omits them).
--
-- All existing protections remain:
--   • booking must belong to p_vendor_id and be status = 'completed'
--   • booking cannot already exist in vendor_settlement_bookings
--   • UNIQUE(booking_id) is enforced at the table level
--   • any failure rolls back the complete batch

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
  -- subtotal_before_tax / tax_amount / commission_base are optional: if the
  -- JSON key is absent, jsonb->>'key' returns NULL and the cast stores NULL.
  FOR v_booking IN SELECT value FROM jsonb_array_elements(p_bookings)
  LOOP
    INSERT INTO vendor_settlement_bookings (
      settlement_id,      booking_id,
      booking_gross,      subtotal_before_tax,
      tax_amount,         commission_base,
      commission_amount,  net_vendor_amount
    ) VALUES (
      v_settlement_id,
      (v_booking->>'booking_id')::UUID,
      (v_booking->>'booking_gross')::NUMERIC,
      (v_booking->>'subtotal_before_tax')::NUMERIC,
      (v_booking->>'tax_amount')::NUMERIC,
      (v_booking->>'commission_base')::NUMERIC,
      (v_booking->>'commission_amount')::NUMERIC,
      (v_booking->>'net_vendor_amount')::NUMERIC
    );
  END LOOP;

  RETURN v_settlement_id;
END;
$$;
