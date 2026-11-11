-- InstaHelp bookings have their own eligibility check
-- (check_vendor_instahelp_eligibility) and must not be blocked by the
-- generic COD subscription gate. Skip that trigger when booking_source
-- is 'instahelp'.

CREATE OR REPLACE FUNCTION fn_enforce_cod_vendor_eligibility()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  -- InstaHelp bookings bypass the COD gate — they use check_vendor_instahelp_eligibility.
  IF NEW.booking_source = 'instahelp' THEN
    RETURN NEW;
  END IF;

  -- Vendor-collected methods: cash, cod.
  -- Any DODO-collected method (razorpay, upi_dodo, online) bypasses this check.
  IF NEW.vendor_id IS NULL
   OR LOWER(COALESCE(NEW.payment_method, '')) NOT IN ('cash', 'cod') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.vendor_id      IS NOT DISTINCT FROM NEW.vendor_id
     AND OLD.payment_method IS NOT DISTINCT FROM NEW.payment_method THEN
    RETURN NEW;
  END IF;

  IF NOT check_vendor_cod_eligibility(NEW.vendor_id) THEN
    RAISE EXCEPTION
      'Vendor % is not eligible to accept vendor-collected bookings. '
      'Verify that the vendor has an active subscription with COD permission.',
      NEW.vendor_id
    USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;
