-- ── Custom Pricing Requests ────────────────────────────────────────────────────
-- Extends vendor_service_requests to support pricing change requests
-- alongside the existing new-service requests.
--
-- Adds:
--   request_type     TEXT  'service' (default) | 'pricing'
--   vendor_service_id UUID  FK to vendor_services (pricing requests only)
--   base_price       NUMERIC  catalog base price at submission time
--   requested_price  NUMERIC  vendor's requested custom price
--
-- Behaviour:
--   • Pricing requests are inserted by the vendor app (anon role).
--   • Existing anon INSERT / SELECT RLS policies already cover them.
--   • The delete_vendor_service_request RPC already enforces status='pending'.
--   • Admin notification trigger updated to emit different text per type.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS request_type TEXT NOT NULL DEFAULT 'service'
    CHECK (request_type IN ('service', 'pricing'));

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS vendor_service_id UUID
    REFERENCES vendor_services(id) ON DELETE SET NULL;

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS base_price NUMERIC(10, 2);

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS requested_price NUMERIC(10, 2);

-- ── Update admin notification trigger ─────────────────────────────────────────
-- Emits 'New Pricing Request' for pricing type; existing text for service type.

CREATE OR REPLACE FUNCTION fn_notify_admin_vendor_service_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_vendor_name TEXT;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'A vendor')
  INTO v_vendor_name
  FROM vendors WHERE id = NEW.vendor_id;

  IF NEW.request_type = 'pricing' THEN
    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'admin', NULL,
      'New Pricing Request',
      COALESCE(v_vendor_name, 'A vendor')
        || ' requested a custom price for "'
        || NEW.service_name || '".',
      'vendor_service_request', 'vendor_service_request', NEW.id,
      FALSE, NOW()
    );
  ELSE
    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'admin', NULL,
      'New Service Request',
      COALESCE(v_vendor_name, 'A vendor')
        || ' requested a new service: "'
        || NEW.service_name || '".',
      'vendor_service_request', 'vendor_service_request', NEW.id,
      FALSE, NOW()
    );
  END IF;
  RETURN NEW;
END;
$$;
