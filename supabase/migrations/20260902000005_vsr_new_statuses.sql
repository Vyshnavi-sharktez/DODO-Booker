-- Replace 'approved' with 'needs_catalog' and 'completed' in the VSR workflow.

-- Step 1: Drop old constraint first so data migration can proceed.
ALTER TABLE vendor_service_requests
  DROP CONSTRAINT IF EXISTS vendor_service_requests_status_check;

-- Step 2: Migrate existing data.
-- 'approved' = admin had accepted but catalog not yet set up → needs_catalog.
UPDATE vendor_service_requests SET status = 'needs_catalog' WHERE status = 'approved';

-- Step 3: Add new constraint.
ALTER TABLE vendor_service_requests
  ADD CONSTRAINT vendor_service_requests_status_check
  CHECK (status IN ('pending', 'needs_catalog', 'completed', 'rejected'));

-- Update vendor notification trigger for new statuses
CREATE OR REPLACE FUNCTION fn_notify_vendor_service_request_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  IF NEW.status = 'needs_catalog' THEN
    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'vendor', NEW.vendor_id,
      'Service Request Accepted',
      'Your request for "' || NEW.service_name || '" has been accepted and is being added to the catalog.',
      'vendor_service_request', 'vendor_service_request', NEW.id,
      FALSE, NOW()
    );
  ELSIF NEW.status = 'completed' THEN
    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'vendor', NEW.vendor_id,
      'Service Request Completed',
      'Your requested service "' || NEW.service_name || '" is now available in the catalog.',
      'vendor_service_request', 'vendor_service_request', NEW.id,
      FALSE, NOW()
    );
  ELSIF NEW.status = 'rejected' THEN
    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'vendor', NEW.vendor_id,
      'Service Request Not Approved',
      'Your request for "' || NEW.service_name || '" was not approved.'
        || CASE
             WHEN NEW.rejection_reason IS NOT NULL
              AND TRIM(NEW.rejection_reason) <> ''
             THEN ' Reason: ' || TRIM(NEW.rejection_reason)
             ELSE ''
           END,
      'vendor_service_request', 'vendor_service_request', NEW.id,
      FALSE, NOW()
    );
  END IF;
  RETURN NEW;
END;
$$;
