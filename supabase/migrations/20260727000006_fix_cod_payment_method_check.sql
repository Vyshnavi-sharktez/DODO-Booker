-- Fix fn_enforce_cod_vendor_eligibility to recognise 'cash' as the canonical
-- Cash-on-Delivery payment method.
--
-- The customer app writes payment_method = 'cash' ("Cash After Service").
-- The original trigger only checked for 'cod', so it never fired for real
-- bookings and the subscription enforcement was silently bypassed.
--
-- This migration replaces the function body so the trigger fires for both
-- 'cash' and 'cod' values.  The trigger definition is unchanged.

CREATE OR REPLACE FUNCTION fn_enforce_cod_vendor_eligibility()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 'cash' = Cash After Service (canonical customer-app value).
  -- 'cod'  = alias accepted for backward compatibility.
  -- Any other payment method (e.g. 'online') bypasses the subscription check.
  IF NEW.vendor_id IS NULL
   OR LOWER(COALESCE(NEW.payment_method, '')) NOT IN ('cash', 'cod') THEN
    RETURN NEW;
  END IF;

  -- UPDATE: skip when neither relevant column actually changed value.
  IF TG_OP = 'UPDATE'
     AND OLD.vendor_id      IS NOT DISTINCT FROM NEW.vendor_id
     AND OLD.payment_method IS NOT DISTINCT FROM NEW.payment_method THEN
    RETURN NEW;
  END IF;

  -- check_vendor_cod_eligibility handles the subscription_enabled gate;
  -- when the module is off it always returns TRUE.
  IF NOT check_vendor_cod_eligibility(NEW.vendor_id) THEN
    RAISE EXCEPTION
      'Vendor % is not eligible to accept COD bookings. '
      'Verify that the vendor has an active subscription and that the '
      'plan includes COD permission.',
      NEW.vendor_id
    USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;
