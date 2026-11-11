-- RPC: create_instahelp_booking_by_admin
-- Admin creates an InstaHelp booking for a customer, assigning to a specific vendor.

CREATE OR REPLACE FUNCTION public.create_instahelp_booking_by_admin(
  p_customer_phone   TEXT,
  p_vendor_id        UUID,
  p_mode_id          UUID,
  p_duration_id      UUID,
  p_service_date     DATE,
  p_scheduled_time   TEXT,
  p_address          TEXT,
  p_payment_method   TEXT DEFAULT 'cash'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id  UUID;
  v_duration     RECORD;
  v_booking_id   UUID;
  v_booking_num  TEXT;
  v_service_name TEXT;
  v_total_price  NUMERIC;
BEGIN
  -- Look up customer by phone
  SELECT id INTO v_customer_id
  FROM public.customers
  WHERE phone = p_customer_phone
  LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'No customer found with phone %', p_customer_phone;
  END IF;

  -- Get duration + mode (verify they belong to the given vendor)
  SELECT d.id, d.label, d.duration_minutes, d.price,
         d.discount_type, d.discount_value, m.mode_type
  INTO v_duration
  FROM public.instahelp_durations d
  JOIN public.instahelp_modes m ON m.id = d.mode_id
  WHERE d.id = p_duration_id
    AND d.mode_id = p_mode_id
    AND m.vendor_id = p_vendor_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Duration not found or does not belong to vendor';
  END IF;

  -- Calculate final price
  v_service_name := 'InstaHelp – ' || v_duration.label;
  v_total_price  := v_duration.price;
  IF v_duration.discount_type = 'percentage' THEN
    v_total_price := v_total_price - (v_total_price * v_duration.discount_value / 100.0);
  ELSIF v_duration.discount_type = 'fixed' THEN
    v_total_price := v_total_price - v_duration.discount_value;
  END IF;
  v_total_price := GREATEST(v_total_price, 0);

  -- Insert booking
  INSERT INTO public.bookings (
    customer_id, vendor_id, service_date, status,
    subtotal, total_amount, discount_amount, tax_amount,
    address, notes, scheduled_time,
    payment_method, payment_status,
    booking_source, assignment_type,
    is_admin_booking
  ) VALUES (
    v_customer_id, p_vendor_id, p_service_date, 'assigned',
    v_total_price, v_total_price, 0, 0,
    p_address, v_service_name, p_scheduled_time,
    p_payment_method, 'pending',
    'instahelp', 'External Vendor',
    true
  )
  RETURNING id, booking_number INTO v_booking_id, v_booking_num;

  -- Insert booking_items
  INSERT INTO public.booking_items (
    booking_id, service_name, quantity, unit_price, total_price
  ) VALUES (
    v_booking_id, v_service_name, 1, v_total_price, v_total_price
  );

  -- Insert instahelp_bookings metadata
  INSERT INTO public.instahelp_bookings (
    booking_id, mode_id, duration_id, mode_type,
    duration_label, duration_minutes, base_price, final_price
  ) VALUES (
    v_booking_id, p_mode_id, p_duration_id, v_duration.mode_type,
    v_duration.label, v_duration.duration_minutes, v_duration.price, v_total_price
  );

  -- Vendor notification
  BEGIN
    INSERT INTO public.notifications (
      user_type, user_id, title, message,
      notification_type, is_read, entity_type, entity_id
    ) VALUES (
      'vendor', p_vendor_id, 'New InstaHelp Booking Assigned',
      'Admin assigned an InstaHelp ' || v_duration.mode_type || ' booking to you.',
      'booking_created', false, 'booking', v_booking_id
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- Customer notification
  BEGIN
    INSERT INTO public.notifications (
      user_type, user_id, title, message,
      notification_type, is_read, entity_type, entity_id
    ) VALUES (
      'customer', v_customer_id, 'InstaHelp Booking Confirmed',
      'Your ' || v_service_name || ' booking has been placed.',
      'booking_created', false, 'booking', v_booking_id
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN json_build_object(
    'booking_id',     v_booking_id,
    'booking_number', v_booking_num
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_instahelp_booking_by_admin TO authenticated;
