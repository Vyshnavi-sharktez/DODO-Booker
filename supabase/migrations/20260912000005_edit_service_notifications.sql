-- Fix admin notification for vendor service requests:
--   • INSERT trigger: skip edit_service (proposal is a staging row, not a
--     direct submission; the real notification fires on first field update).
--   • New UPDATE trigger: fires when warranty or content fields actually
--     change on an edit_service proposal, using field-specific titles.
--   • Status-change trigger: add edit_service → vendor notification when
--     the proposal is approved (completed) or rejected.

-- ── 1. Update INSERT trigger (skip edit_service) ─────────────────────────────

CREATE OR REPLACE FUNCTION fn_notify_admin_vendor_service_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_vendor_name TEXT;
BEGIN
  -- edit_service proposals are staging rows; admin is notified via the
  -- UPDATE trigger (fn_notify_admin_vendor_service_edit) once actual
  -- fields change.
  IF NEW.request_type = 'edit_service' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'A vendor')
  INTO v_vendor_name
  FROM vendors WHERE id = NEW.vendor_id;

  INSERT INTO notifications (
    user_type, user_id, title, message,
    notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'admin', NULL,
    CASE NEW.request_type
      WHEN 'price_change'   THEN 'Price Change Request'
      WHEN 'delete_service' THEN 'Service Deletion Request'
      ELSE 'New Service Request'
    END,
    CASE NEW.request_type
      WHEN 'price_change'   THEN v_vendor_name || ' requested a price change for "' || NEW.service_name || '".'
      WHEN 'delete_service' THEN v_vendor_name || ' requested deletion of "' || NEW.service_name || '".'
      ELSE v_vendor_name || ' requested a new service: "' || NEW.service_name || '".'
    END,
    'vendor_service_request', 'vendor_service_request', NEW.id,
    FALSE, NOW()
  );
  RETURN NEW;
END;
$$;

-- ── 2. New UPDATE trigger: admin notification for edit_service field changes ──

CREATE OR REPLACE FUNCTION fn_notify_admin_vendor_service_edit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_vendor_name TEXT;
  v_title       TEXT;
  v_message     TEXT;
  v_sections    TEXT[] := '{}';
  v_sections_str TEXT;
BEGIN
  -- Only fire for pending edit_service rows that didn't change status.
  IF NEW.request_type <> 'edit_service'
     OR NEW.status    <> 'pending'
     OR OLD.status    <> 'pending'
  THEN
    RETURN NEW;
  END IF;

  -- Detect warranty changes.
  IF (OLD.warranty_enabled    IS DISTINCT FROM NEW.warranty_enabled)
  OR (OLD.warranty_days        IS DISTINCT FROM NEW.warranty_days)
  OR (OLD.warranty_covers      IS DISTINCT FROM NEW.warranty_covers)
  OR (OLD.warranty_exclusions  IS DISTINCT FROM NEW.warranty_exclusions)
  THEN
    v_sections := v_sections || ARRAY['warranty'];
  END IF;

  -- Detect content changes (included / excluded / before-after).
  IF (OLD.included_items::text    IS DISTINCT FROM NEW.included_items::text)
  OR (OLD.excluded_items::text    IS DISTINCT FROM NEW.excluded_items::text)
  OR (OLD.before_after_pairs::text IS DISTINCT FROM NEW.before_after_pairs::text)
  THEN
    v_sections := v_sections || ARRAY['content'];
  END IF;

  IF array_length(v_sections, 1) IS NULL THEN
    -- No tracked fields changed; skip.
    RETURN NEW;
  END IF;

  -- Choose a specific title when only one section changed.
  v_title := CASE
    WHEN v_sections = ARRAY['warranty'] THEN 'Warranty Edit Pending Review'
    WHEN v_sections = ARRAY['content']  THEN 'Service Content Edit Pending Review'
    ELSE 'Service Edit Pending Review'
  END;

  v_sections_str := array_to_string(v_sections, ', ');

  SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'A vendor')
  INTO v_vendor_name
  FROM vendors WHERE id = NEW.vendor_id;

  v_message := v_vendor_name
    || ' updated "' || NEW.service_name || '" ('
    || v_sections_str || ') — pending review.';

  INSERT INTO notifications (
    user_type, user_id, title, message,
    notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'admin', NULL,
    v_title, v_message,
    'vendor_service_request', 'vendor_service_request', NEW.id,
    FALSE, NOW()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_vendor_service_edit ON vendor_service_requests;
CREATE TRIGGER trg_notify_admin_vendor_service_edit
  AFTER UPDATE ON vendor_service_requests
  FOR EACH ROW EXECUTE FUNCTION fn_notify_admin_vendor_service_edit();

-- ── 3. Update vendor status-change trigger to handle edit_service ─────────────

CREATE OR REPLACE FUNCTION fn_notify_vendor_service_request_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  IF NEW.request_type = 'price_change' THEN
    IF NEW.status = 'completed' THEN
      INSERT INTO notifications (user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at)
      VALUES ('vendor', NEW.vendor_id, 'Price Change Approved',
        'Your price change request for "' || NEW.service_name || '" has been approved. The new price is now active.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW());
    ELSIF NEW.status = 'rejected' THEN
      INSERT INTO notifications (user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at)
      VALUES ('vendor', NEW.vendor_id, 'Price Change Not Approved',
        'Your price change request for "' || NEW.service_name || '" was not approved.'
          || CASE WHEN NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> ''
                  THEN ' Reason: ' || TRIM(NEW.rejection_reason) ELSE '' END,
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW());
    END IF;

  ELSIF NEW.request_type = 'delete_service' THEN
    IF NEW.status = 'completed' THEN
      INSERT INTO notifications (user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at)
      VALUES ('vendor', NEW.vendor_id, 'Service Deletion Approved',
        'Your request to delete "' || NEW.service_name || '" has been approved. The service has been removed.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW());
    ELSIF NEW.status = 'rejected' THEN
      INSERT INTO notifications (user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at)
      VALUES ('vendor', NEW.vendor_id, 'Deletion Request Not Approved',
        'Your request to delete "' || NEW.service_name || '" was not approved.'
          || CASE WHEN NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> ''
                  THEN ' Reason: ' || TRIM(NEW.rejection_reason) ELSE '' END,
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW());
    END IF;

  ELSIF NEW.request_type = 'edit_service' THEN
    IF NEW.status = 'completed' THEN
      INSERT INTO notifications (user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at)
      VALUES ('vendor', NEW.vendor_id, 'Service Edits Approved',
        'Your proposed edits to "' || NEW.service_name || '" have been approved and are now live.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW());
    ELSIF NEW.status = 'rejected' THEN
      INSERT INTO notifications (user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at)
      VALUES ('vendor', NEW.vendor_id, 'Service Edits Not Approved',
        'Your proposed edits to "' || NEW.service_name || '" were not approved.'
          || CASE WHEN NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> ''
                  THEN ' Reason: ' || TRIM(NEW.rejection_reason) ELSE '' END,
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW());
    END IF;

  ELSE
    -- new_service type
    IF NEW.status = 'needs_catalog' THEN
      INSERT INTO notifications (user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at)
      VALUES ('vendor', NEW.vendor_id, 'Service Request Accepted',
        'Your request for "' || NEW.service_name || '" has been accepted. It will appear in My Services once catalog setup is complete.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW());
    ELSIF NEW.status = 'completed' THEN
      INSERT INTO notifications (user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at)
      VALUES ('vendor', NEW.vendor_id, 'Service Now Active',
        '"' || NEW.service_name || '" is now active and available in My Services → Custom Services.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW());
    ELSIF NEW.status = 'rejected' THEN
      INSERT INTO notifications (user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at)
      VALUES ('vendor', NEW.vendor_id, 'Service Request Not Approved',
        'Your request for "' || NEW.service_name || '" was not approved.'
          || CASE WHEN NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> ''
                  THEN ' Reason: ' || TRIM(NEW.rejection_reason) ELSE '' END,
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW());
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
