-- Fix fn_notify_vendor_service_request_status for the new_service type:
--
--   needs_catalog: was "now available in your Custom Services" — wrong, the
--                  service only becomes available after admin marks it completed.
--                  Updated to reflect that catalog setup is in progress.
--
--   completed:     was "now available in the catalog" — vague. Updated to tell
--                  the vendor the service is now in My Services → Custom Services.
--
-- All other branches (price_change, delete_service, rejected) are unchanged.

CREATE OR REPLACE FUNCTION fn_notify_vendor_service_request_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  IF NEW.request_type = 'price_change' THEN
    IF NEW.status = 'completed' THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Price Change Approved',
        'Your price change request for "' || NEW.service_name || '" has been approved. The new price is now active.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );
    ELSIF NEW.status = 'rejected' THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Price Change Not Approved',
        'Your price change request for "' || NEW.service_name || '" was not approved.'
          || CASE WHEN NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> ''
                  THEN ' Reason: ' || TRIM(NEW.rejection_reason) ELSE '' END,
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );
    END IF;

  ELSIF NEW.request_type = 'delete_service' THEN
    IF NEW.status = 'completed' THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Service Deletion Approved',
        'Your request to delete "' || NEW.service_name || '" has been approved. The service has been removed.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );
    ELSIF NEW.status = 'rejected' THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Deletion Request Not Approved',
        'Your request to delete "' || NEW.service_name || '" was not approved.'
          || CASE WHEN NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> ''
                  THEN ' Reason: ' || TRIM(NEW.rejection_reason) ELSE '' END,
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );
    END IF;

  ELSE
    -- new_service type
    IF NEW.status = 'needs_catalog' THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Service Request Accepted',
        'Your request for "' || NEW.service_name || '" has been accepted. It will appear in My Services once catalog setup is complete.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );
    ELSIF NEW.status = 'completed' THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Service Now Active',
        '"' || NEW.service_name || '" is now active and available in My Services → Custom Services.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );
    ELSIF NEW.status = 'rejected' THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Service Request Not Approved',
        'Your request for "' || NEW.service_name || '" was not approved.'
          || CASE WHEN NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> ''
                  THEN ' Reason: ' || TRIM(NEW.rejection_reason) ELSE '' END,
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );
    END IF;
    -- 'deleted' status is set internally; no separate vendor notification needed
    -- (vendor is already notified via the delete_service request completing)
  END IF;

  RETURN NEW;
END;
$$;
