-- ── Remove Custom Pricing Feature ────────────────────────────────────────────
--
-- The custom pricing / pricing request feature is removed.
-- Vendors now always use catalog prices; new services go through the
-- existing Create Service flow.
--
-- 1. Drop the update_vendor_service_custom_price RPC.
-- 2. Restore the admin notification trigger to service-only logic.
-- 3. Drop pricing-request-specific columns from vendor_service_requests.
-- 4. Drop the custom_price column from vendor_services.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Drop custom price RPC
DROP FUNCTION IF EXISTS update_vendor_service_custom_price(UUID, UUID, NUMERIC);

-- 2. Simplify admin notification trigger (all remaining requests are service type)
CREATE OR REPLACE FUNCTION fn_notify_admin_vendor_service_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_vendor_name TEXT;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'A vendor')
  INTO v_vendor_name
  FROM vendors WHERE id = NEW.vendor_id;

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
  RETURN NEW;
END;
$$;

-- 3. Drop pricing-request-specific columns from vendor_service_requests
--    (FK column first, then the rest)
ALTER TABLE vendor_service_requests
  DROP COLUMN IF EXISTS vendor_service_id,
  DROP COLUMN IF EXISTS request_type,
  DROP COLUMN IF EXISTS base_price,
  DROP COLUMN IF EXISTS requested_price;

-- 4. Drop custom_price from vendor_services
ALTER TABLE vendor_services
  DROP COLUMN IF EXISTS custom_price;
