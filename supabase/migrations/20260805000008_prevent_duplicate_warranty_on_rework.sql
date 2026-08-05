-- Migration: Prevent duplicate warranty generation for warranty rework bookings

CREATE OR REPLACE FUNCTION public.fn_auto_generate_service_warranty()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_warranty_days INT := 30;
  v_expires_at TIMESTAMPTZ;
BEGIN
  -- Trigger when booking transitions to completed
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN

    -- 1. Check if this booking is a warranty rework booking.
    -- Warranty certificates must ONLY be generated for normal completed service bookings, NEVER for rework bookings.
    IF EXISTS (SELECT 1 FROM public.service_warranties WHERE rework_booking_id = NEW.id)
       OR (NEW.notes IS NOT NULL AND NEW.notes LIKE '%[WARRANTY REWORK]%') THEN
      RETURN NEW;
    END IF;

    -- 2. Prevent duplicate warranty creation for the same original booking
    IF NOT EXISTS (SELECT 1 FROM public.service_warranties WHERE booking_id = NEW.id) THEN
      -- Read default warranty duration from settings
      SELECT COALESCE(NULLIF(TRIM(setting_value), '')::INT, 30) INTO v_warranty_days
      FROM public.settings
      WHERE setting_key = 'default_warranty_days';

      IF v_warranty_days <= 0 THEN
        v_warranty_days := 30;
      END IF;

      v_expires_at := now() + (v_warranty_days || ' days')::INTERVAL;

      INSERT INTO public.service_warranties (
        booking_id,
        customer_id,
        vendor_id,
        warranty_days,
        issued_at,
        expires_at,
        status,
        created_at,
        updated_at
      ) VALUES (
        NEW.id,
        NEW.customer_id,
        NEW.vendor_id,
        v_warranty_days,
        now(),
        v_expires_at,
        'Active',
        now(),
        now()
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Clean up any erroneous duplicate warranties that were previously generated for rework bookings
DELETE FROM public.service_warranties
WHERE booking_id IN (
  SELECT b.id
  FROM public.bookings b
  JOIN public.service_warranties sw ON sw.rework_booking_id = b.id
)
OR (
  booking_id IN (
    SELECT id FROM public.bookings WHERE notes LIKE '%[WARRANTY REWORK]%'
  )
);
