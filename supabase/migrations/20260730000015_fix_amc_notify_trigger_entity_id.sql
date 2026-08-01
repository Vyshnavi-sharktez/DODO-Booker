-- Fix: notifications.entity_id is a UUID column; the explicit ::text cast
-- on NEW.id caused "expression is of type text" errors. Pass NEW.id directly.

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
  SELECT EXISTS (
    SELECT 1 FROM notifications
    WHERE entity_type = 'amc_scheduling_request'
      AND entity_id   = NEW.id
  ) INTO v_already_exists;

  IF v_already_exists THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'A customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  SELECT COALESCE(NULLIF(TRIM(service_name), ''), 'a service')
  INTO   v_service_name
  FROM   amc_contracts
  WHERE  id = NEW.amc_contract_id;
  v_service_name := COALESCE(v_service_name, 'a service');

  IF NEW.preferred_date IS NOT NULL THEN
    v_preferred_date := TO_CHAR(NEW.preferred_date, 'DD Mon YYYY');
  END IF;

  v_message := v_customer_name || ' requested a visit for ' || v_service_name || '.';
  IF v_preferred_date IS NOT NULL THEN
    v_message := v_message || ' Preferred: ' || v_preferred_date || '.';
  END IF;
  IF NEW.notes IS NOT NULL AND TRIM(NEW.notes) <> '' THEN
    v_message := v_message || ' Note: "' || TRIM(NEW.notes) || '"';
  END IF;

  INSERT INTO notifications (
    user_type, user_id, title, message,
    notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'admin', NULL, 'New AMC Visit Request', v_message,
    'amc_scheduling_request', 'amc_scheduling_request', NEW.id,
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_notify_admin_amc_request_cancelled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name TEXT;
  v_service_name  TEXT;
BEGIN
  IF OLD.status <> 'pending' OR NEW.status <> 'cancelled_by_customer' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'A customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  SELECT COALESCE(NULLIF(TRIM(service_name), ''), 'a service')
  INTO   v_service_name
  FROM   amc_contracts
  WHERE  id = NEW.amc_contract_id;
  v_service_name := COALESCE(v_service_name, 'a service');

  INSERT INTO notifications (
    user_type, user_id, title, message,
    notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'admin', NULL, 'AMC Request Cancelled',
    v_customer_name || ' cancelled their scheduling request for ' || v_service_name || '.',
    'amc_scheduling_request', 'amc_scheduling_request', NEW.id,
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;
