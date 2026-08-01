-- Fix trigger function: NEW.id::TEXT was passed to notifications.entity_id (uuid).
-- The explicit ::TEXT cast converts the uuid to text, then Postgres cannot coerce
-- it back to uuid implicitly, causing SQLSTATE 42804.  Drop the cast — NEW.id is
-- already uuid and inserts directly into the uuid column.

CREATE OR REPLACE FUNCTION public.fn_notify_admin_amc_cancellation_requested()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name TEXT;
BEGIN
  IF NEW.status = 'cancellation_requested' AND OLD.status <> 'cancellation_requested' THEN
    SELECT COALESCE(NULLIF(TRIM(full_name), ''), phone, 'A customer')
      INTO v_customer_name
      FROM customers
      WHERE id = NEW.customer_id;

    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, is_read, entity_type, entity_id
    ) VALUES (
      'admin',
      NULL,
      'AMC Cancellation Requested',
      COALESCE(v_customer_name, 'A customer') ||
        ' has requested cancellation of their "' || NEW.plan_name || '" AMC contract.' ||
        ' Reason: ' || COALESCE(NEW.cancellation_reason, 'Not specified') || '.',
      'amc_cancellation_requested',
      FALSE,
      'amc_contract',
      NEW.id
    );
  END IF;
  RETURN NEW;
END;
$$;
