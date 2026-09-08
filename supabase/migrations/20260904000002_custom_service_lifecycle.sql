-- ── Custom Service Lifecycle ──────────────────────────────────────────────────
-- Extends vendor_service_requests to support:
--   1. Price-change requests for approved custom services
--   2. Deletion requests for approved custom services
-- All sent to Admin as Service Requests (no separate pricing tab).
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Add request_type column (default 'new_service' for existing rows)
ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS request_type TEXT NOT NULL DEFAULT 'new_service';

ALTER TABLE vendor_service_requests
  DROP CONSTRAINT IF EXISTS vsr_request_type_check;
ALTER TABLE vendor_service_requests
  ADD CONSTRAINT vsr_request_type_check
    CHECK (request_type IN ('new_service', 'price_change', 'delete_service'));

-- 2. Add parent_request_id (price_change / delete_service → original new_service row)
ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS parent_request_id UUID
    REFERENCES vendor_service_requests(id) ON DELETE SET NULL;

-- 3. Add new_price (price_change requests only — the proposed price)
ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS new_price NUMERIC(10, 2);

-- 4. Extend status check to include 'deleted'
--    (set on the original new_service row when admin approves a delete_service request)
ALTER TABLE vendor_service_requests
  DROP CONSTRAINT IF EXISTS vendor_service_requests_status_check;
ALTER TABLE vendor_service_requests
  ADD CONSTRAINT vendor_service_requests_status_check
    CHECK (status IN ('pending', 'needs_catalog', 'completed', 'rejected', 'deleted'));

-- 5. Admin accept RPC — handles all request types with a single call
CREATE OR REPLACE FUNCTION admin_accept_service_request(p_request_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_req RECORD;
BEGIN
  -- Admin-only guard
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO v_req
  FROM vendor_service_requests WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Service request % not found', p_request_id;
  END IF;

  IF v_req.request_type = 'new_service' THEN
    -- Standard flow: move to needs_catalog; admin marks completed later
    UPDATE vendor_service_requests
      SET status = 'needs_catalog'
      WHERE id = p_request_id;

  ELSIF v_req.request_type = 'price_change' THEN
    -- Apply the new price to the original service (status unchanged on original)
    UPDATE vendor_service_requests
      SET price = v_req.new_price
      WHERE id = v_req.parent_request_id;
    -- Mark the price_change request itself as completed
    UPDATE vendor_service_requests
      SET status = 'completed'
      WHERE id = p_request_id;

  ELSIF v_req.request_type = 'delete_service' THEN
    -- Mark the original service as deleted
    UPDATE vendor_service_requests
      SET status = 'deleted'
      WHERE id = v_req.parent_request_id;
    -- Mark the delete_service request as completed
    UPDATE vendor_service_requests
      SET status = 'completed'
      WHERE id = p_request_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_accept_service_request(UUID) TO authenticated;

-- 6. Update admin notification trigger for the three request types
CREATE OR REPLACE FUNCTION fn_notify_admin_vendor_service_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_vendor_name TEXT;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'A vendor')
  INTO v_vendor_name
  FROM vendors WHERE id = NEW.vendor_id;

  IF NEW.request_type = 'price_change' THEN
    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'admin', NULL, 'Price Change Request',
      v_vendor_name || ' requested a price change for "' || NEW.service_name || '".',
      'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
    );
  ELSIF NEW.request_type = 'delete_service' THEN
    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'admin', NULL, 'Service Deletion Request',
      v_vendor_name || ' requested deletion of "' || NEW.service_name || '".',
      'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
    );
  ELSE
    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'admin', NULL, 'New Service Request',
      v_vendor_name || ' requested a new service: "' || NEW.service_name || '".',
      'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
    );
  END IF;
  RETURN NEW;
END;
$$;

-- 7. Update vendor notification trigger — per request_type and status
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
        'Your request for "' || NEW.service_name || '" has been accepted and is now available in your Custom Services.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );
    ELSIF NEW.status = 'completed' THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Service Request Completed',
        'Your requested service "' || NEW.service_name || '" is now available in the catalog.',
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
