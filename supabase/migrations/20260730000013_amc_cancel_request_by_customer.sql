-- Adds 'cancelled_by_customer' status to amc_scheduling_requests so that
-- customer-initiated cancels are distinguishable from system cancels
-- (e.g. when the full AMC contract is cancelled, which sets status → 'cancelled').
-- This distinction allows the admin notification trigger to fire only when the
-- customer explicitly cancels a pending request.

-- ── Extend status check constraint ───────────────────────────────────────────

ALTER TABLE amc_scheduling_requests
  DROP CONSTRAINT IF EXISTS amc_scheduling_requests_status_check;

ALTER TABLE amc_scheduling_requests
  ADD CONSTRAINT amc_scheduling_requests_status_check
  CHECK (status IN (
    'pending',
    'scheduled',
    'cancelled',
    'rejected',
    'cancelled_by_customer'
  ));

-- ── Admin notification on customer-initiated cancel ───────────────────────────
-- Fires AFTER UPDATE when status transitions from 'pending' → 'cancelled_by_customer'.
-- SECURITY DEFINER so the anon caller can trigger the INSERT into notifications.

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
  -- Only fire on the specific pending → cancelled_by_customer transition.
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
    'AMC Request Cancelled',
    v_customer_name || ' cancelled their scheduling request for ' || v_service_name || '.',
    'amc_scheduling_request',
    'amc_scheduling_request',
    NEW.id,
    FALSE,
    NOW()
  );

  RAISE LOG '[DODO][AMCRequest] Cancel notification sent for request % (customer: %, service: %)',
    NEW.id, v_customer_name, v_service_name;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_amc_cancel ON amc_scheduling_requests;

CREATE TRIGGER trg_notify_admin_amc_cancel
  AFTER UPDATE OF status ON amc_scheduling_requests
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_admin_amc_request_cancelled();
