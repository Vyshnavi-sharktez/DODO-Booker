-- Notify vendor when is_preferred_vendor is turned on.
-- Fires for both individual edits and bulk updates.

CREATE OR REPLACE FUNCTION public.notify_vendor_preferred_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.is_preferred_vendor = TRUE
     AND (OLD.is_preferred_vendor IS NULL OR OLD.is_preferred_vendor = FALSE)
  THEN
    INSERT INTO public.notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'vendor', NEW.id,
      'You are now a Preferred Vendor!',
      'Congratulations! You have been added as a preferred vendor on the platform. Customers can now select you directly when booking.',
      'preferred_vendor_status', 'vendor', NEW.id, FALSE, NOW()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_vendor_preferred ON public.vendors;

CREATE TRIGGER trg_notify_vendor_preferred
  AFTER UPDATE OF is_preferred_vendor ON public.vendors
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_vendor_preferred_status();
