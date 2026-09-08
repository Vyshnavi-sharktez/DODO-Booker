-- Replace the create-a-new-row deletion flow with an inline status transition.
--
-- Before: vendor submits a separate delete_service row (parent_request_id → original).
-- After:  vendor updates the original new_service row to status='pending_deletion'.
--         Admin accepts  → status='deleted'   (service gone from Custom Services).
--         Admin rejects  → status='completed' (service restored, active again).
--
-- No new rows are created. The original request history is preserved.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Extend status constraint to include 'pending_deletion'
ALTER TABLE vendor_service_requests
  DROP CONSTRAINT IF EXISTS vendor_service_requests_status_check;
ALTER TABLE vendor_service_requests
  ADD CONSTRAINT vendor_service_requests_status_check
    CHECK (status IN (
      'pending', 'needs_catalog', 'completed', 'rejected',
      'deleted', 'pending_deletion'
    ));

-- 2. Vendor RPC: mark an approved custom service as pending deletion.
--    Vendor app runs as anon (no Supabase Auth session), so p_vendor_id is
--    passed from the client and validated inside the function.
--    Only allowed when: request_type='new_service' AND status='completed'.
CREATE OR REPLACE FUNCTION vendor_request_deletion(
  p_request_id UUID,
  p_vendor_id  UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_count INT;
BEGIN
  UPDATE vendor_service_requests
    SET status = 'pending_deletion'
  WHERE id          = p_request_id
    AND vendor_id   = p_vendor_id
    AND request_type = 'new_service'
    AND status       = 'completed';

  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count = 0 THEN
    RAISE EXCEPTION 'Service request not found or not eligible for deletion'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION vendor_request_deletion(UUID, UUID) TO anon, authenticated;

-- 3. Update admin_accept_service_request to handle pending_deletion.
--    new_service + pending          → needs_catalog   (unchanged)
--    new_service + pending_deletion → deleted         (NEW)
--    price_change / delete_service  → unchanged
CREATE OR REPLACE FUNCTION admin_accept_service_request(p_request_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_req RECORD;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO v_req
  FROM vendor_service_requests WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Service request % not found', p_request_id;
  END IF;

  IF v_req.request_type = 'new_service' THEN
    IF v_req.status = 'pending_deletion' THEN
      -- Admin approves deletion: mark the service as deleted
      UPDATE vendor_service_requests
        SET status = 'deleted'
        WHERE id = p_request_id;
    ELSE
      -- Standard accept: move to needs_catalog for catalog setup
      UPDATE vendor_service_requests
        SET status = 'needs_catalog'
        WHERE id = p_request_id;
    END IF;

  ELSIF v_req.request_type = 'price_change' THEN
    UPDATE vendor_service_requests
      SET price = v_req.new_price
      WHERE id = v_req.parent_request_id;
    UPDATE vendor_service_requests
      SET status = 'completed'
      WHERE id = p_request_id;

  ELSIF v_req.request_type = 'delete_service' THEN
    -- Backward compat for any pre-existing delete_service rows
    UPDATE vendor_service_requests
      SET status = 'deleted'
      WHERE id = v_req.parent_request_id;
    UPDATE vendor_service_requests
      SET status = 'completed'
      WHERE id = p_request_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_accept_service_request(UUID) TO authenticated;

-- 4. Admin reject RPC: replaces the direct-update reject() path.
--    pending_deletion → completed  (deletion rejected; service stays active)
--    everything else  → rejected   (standard rejection)
--    Reason is stored in rejection_reason for the notification trigger to use.
CREATE OR REPLACE FUNCTION admin_reject_service_request(
  p_request_id UUID,
  p_reason     TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_req RECORD;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO v_req
  FROM vendor_service_requests WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Service request % not found', p_request_id;
  END IF;

  IF v_req.status = 'pending_deletion' THEN
    -- Deletion rejected: restore the service to active
    UPDATE vendor_service_requests
      SET status = 'completed',
          rejection_reason = NULLIF(TRIM(p_reason), '')
      WHERE id = p_request_id;
  ELSE
    -- Standard rejection
    UPDATE vendor_service_requests
      SET status = 'rejected',
          rejection_reason = NULLIF(TRIM(p_reason), '')
      WHERE id = p_request_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_reject_service_request(UUID, TEXT) TO authenticated;

-- 5. Notify admin when a vendor marks a service as pending_deletion.
--    The existing INSERT trigger only fires for new rows; deletion requests
--    are now UPDATEs, so we notify admin inside this UPDATE trigger instead.
--
--    Also handles vendor notifications for:
--      pending_deletion → deleted   (admin approved deletion)
--      pending_deletion → completed (admin rejected deletion)
--
--    All other branches are carried over unchanged from migration 20260904000004.
CREATE OR REPLACE FUNCTION fn_notify_vendor_service_request_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  -- ── Admin notification: vendor requested deletion ──────────────────────────
  IF NEW.status = 'pending_deletion' THEN
    DECLARE v_vendor_name TEXT;
    BEGIN
      SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'A vendor')
      INTO v_vendor_name
      FROM vendors WHERE id = NEW.vendor_id;

      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'admin', NULL, 'Service Deletion Request',
        v_vendor_name || ' requested deletion of "' || NEW.service_name || '".',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );
    END;
    RETURN NEW;
  END IF;

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

    ELSIF NEW.status = 'deleted' AND OLD.status = 'pending_deletion' THEN
      -- Admin approved the inline deletion request
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Service Deletion Approved',
        'Your request to delete "' || NEW.service_name || '" has been approved. The service has been removed from your Custom Services.',
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );

    ELSIF NEW.status = 'completed' AND OLD.status = 'pending_deletion' THEN
      -- Admin rejected the deletion; service is restored to active
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id, 'Deletion Request Not Approved',
        'Your request to delete "' || NEW.service_name || '" was not approved. The service remains active.'
          || CASE WHEN NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> ''
                  THEN ' Reason: ' || TRIM(NEW.rejection_reason) ELSE '' END,
        'vendor_service_request', 'vendor_service_request', NEW.id, FALSE, NOW()
      );

    ELSIF NEW.status = 'completed' THEN
      -- Catalog setup done; service is now active in Custom Services
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
    -- 'deleted' from other states is set internally; no vendor notification needed
  END IF;

  RETURN NEW;
END;
$$;
