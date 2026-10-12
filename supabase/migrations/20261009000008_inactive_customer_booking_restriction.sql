-- Prevent inactive customers from creating new bookings.
-- Mirrors the pattern used in admin_create_refund_request and
-- fn_check_custom_service_bookable — raise before the row is inserted.

CREATE OR REPLACE FUNCTION fn_check_customer_active_on_booking()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM customers WHERE id = NEW.customer_id AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Your account is currently unable to place new bookings. Please contact our support team for assistance.'
      USING ERRCODE = 'P0003';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_customer_active_on_booking ON bookings;

CREATE TRIGGER trg_check_customer_active_on_booking
  BEFORE INSERT ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_check_customer_active_on_booking();
