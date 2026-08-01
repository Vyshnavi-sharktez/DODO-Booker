-- Admin notification trigger for AMC scheduling requests.
-- Fires AFTER INSERT so the admin is alerted the moment a customer submits a
-- visit request. SECURITY DEFINER lets the function INSERT into notifications
-- even though the caller is the anon role (customer app, no auth.signIn).

CREATE OR REPLACE FUNCTION fn_notify_admin_amc_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name  TEXT;
  v_service_name   TEXT;
  v_preferred_date TEXT;
  v_message        TEXT;
  v_already_exists BOOLEAN;
BEGIN
  -- Duplicate guard: if a notification for this exact request already exists,
  -- skip silently (guards against retried inserts).
  SELECT EXISTS (
    SELECT 1 FROM notifications
    WHERE entity_type = 'amc_scheduling_request'
      AND entity_id   = NEW.id
  ) INTO v_already_exists;

  IF v_already_exists THEN
    RAISE LOG '[DODO][AMCRequest] Duplicate notification prevented for request %', NEW.id;
    RETURN NEW;
  END IF;

  -- Resolve customer full name.
  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'A customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id;

  v_customer_name := COALESCE(v_customer_name, 'A customer');

  -- Resolve service name from the linked AMC contract.
  SELECT COALESCE(NULLIF(TRIM(service_name), ''), 'a service')
  INTO   v_service_name
  FROM   amc_contracts
  WHERE  id = NEW.amc_contract_id;

  v_service_name := COALESCE(v_service_name, 'a service');

  -- Format preferred date if set.
  IF NEW.preferred_date IS NOT NULL THEN
    v_preferred_date := TO_CHAR(NEW.preferred_date, 'DD Mon YYYY');
  END IF;

  -- Build message: base + optional preferred date + optional notes.
  v_message := v_customer_name || ' requested a visit for ' || v_service_name || '.';
  IF v_preferred_date IS NOT NULL THEN
    v_message := v_message || ' Preferred: ' || v_preferred_date || '.';
  END IF;
  IF NEW.notes IS NOT NULL AND TRIM(NEW.notes) <> '' THEN
    v_message := v_message || ' Note: "' || TRIM(NEW.notes) || '"';
  END IF;

  INSERT INTO notifications (
    user_type,
    user_id,
    title,
    message,
    notification_type,
    entity_type,
    entity_id,
    is_read,
    created_at
  ) VALUES (
    'admin',
    NULL,
    'New AMC Visit Request',
    v_message,
    'amc_scheduling_request',
    'amc_scheduling_request',
    NEW.id,
    FALSE,
    NOW()
  );

  RAISE LOG '[DODO][AMCRequest] Admin notification created for request % (customer: %, service: %)',
    NEW.id, v_customer_name, v_service_name;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_amc_request ON amc_scheduling_requests;

CREATE TRIGGER trg_notify_admin_amc_request
  AFTER INSERT ON amc_scheduling_requests
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_admin_amc_request();
