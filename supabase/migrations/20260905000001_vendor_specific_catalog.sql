-- ── Vendor Specific Catalog ───────────────────────────────────────────────────
-- 1. active_price on vendor_service_requests: the current live price shown to
--    customers.  Set to `price` on new_service acceptance, updated on each
--    approved price_change.
-- 2. custom_service_id on booking_items: nullable FK used instead of service_id
--    when a booking item is a vendor custom service.
-- 3. service_id on booking_items: made nullable so custom-only bookings can
--    leave it NULL (it was always a denormalized convenience column).
-- 4. admin_accept_service_request RPC: new_service now goes directly to
--    completed (no needs_catalog waypoint) and sets active_price.
--    price_change acceptance also updates parent's active_price.

-- ────────────────────────────────────────────────────────────────────────────
-- Column additions
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS active_price NUMERIC(10,2);

ALTER TABLE booking_items
  ADD COLUMN IF NOT EXISTS custom_service_id UUID
    REFERENCES vendor_service_requests(id) ON DELETE SET NULL;

-- service_id was implicitly required but has no DB NOT NULL constraint in most
-- deployments; ensure the FK itself stays but the column is nullable.
ALTER TABLE booking_items
  ALTER COLUMN service_id DROP NOT NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- Backfill: existing completed new_service rows get active_price = price
-- ────────────────────────────────────────────────────────────────────────────

UPDATE vendor_service_requests
SET active_price = price
WHERE request_type = 'new_service'
  AND status IN ('completed', 'pending_deletion', 'deleted')
  AND active_price IS NULL
  AND price IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- Replace admin_accept_service_request RPC
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_accept_service_request(
  p_request_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req  vendor_service_requests%ROWTYPE;
  v_uid  UUID := auth.uid();
BEGIN
  -- Authenticate: caller must be a signed-in admin user
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_req
  FROM vendor_service_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found: %', p_request_id;
  END IF;

  -- ── new_service ─────────────────────────────────────────────────────────
  IF v_req.request_type = 'new_service' THEN

    IF v_req.status = 'pending_deletion' THEN
      -- Approve the deletion: mark service deleted
      UPDATE vendor_service_requests
      SET status = 'deleted', updated_at = NOW()
      WHERE id = p_request_id;

      -- Notify vendor: deletion approved
      INSERT INTO vendor_notifications(vendor_id, title, body, type, reference_id)
      VALUES (
        v_req.vendor_id,
        'Service Removal Approved',
        'Your request to remove "' || v_req.service_name || '" has been approved. It is no longer available.',
        'service_request',
        p_request_id
      );

    ELSE
      -- Standard accept: new_service → completed immediately, set active_price
      UPDATE vendor_service_requests
      SET status = 'completed',
          active_price = price,
          updated_at = NOW()
      WHERE id = p_request_id;

      -- Notify vendor: service is now live
      INSERT INTO vendor_notifications(vendor_id, title, body, type, reference_id)
      VALUES (
        v_req.vendor_id,
        'Custom Service Approved',
        'Your service "' || v_req.service_name || '" has been approved and is now live for customers.',
        'service_request',
        p_request_id
      );
    END IF;

  -- ── price_change ─────────────────────────────────────────────────────────
  ELSIF v_req.request_type = 'price_change' THEN

    -- Update the parent new_service row: both price and active_price
    UPDATE vendor_service_requests
    SET price = v_req.new_price,
        active_price = v_req.new_price,
        updated_at = NOW()
    WHERE id = v_req.parent_request_id;

    -- Mark this price_change request as completed
    UPDATE vendor_service_requests
    SET status = 'completed', updated_at = NOW()
    WHERE id = p_request_id;

    -- Notify vendor: price change approved
    INSERT INTO vendor_notifications(vendor_id, title, body, type, reference_id)
    SELECT
      v_req.vendor_id,
      'Price Change Approved',
      'The price for "' || v_req.service_name || '" has been updated to ₹' ||
        ROUND(v_req.new_price)::TEXT || '.',
      'service_request',
      p_request_id
    WHERE v_req.new_price IS NOT NULL;

  -- ── delete_service (legacy row-type; now handled via pending_deletion) ───
  ELSIF v_req.request_type = 'delete_service' THEN

    -- Mark the referenced parent service as deleted
    UPDATE vendor_service_requests
    SET status = 'deleted', updated_at = NOW()
    WHERE id = v_req.parent_request_id;

    UPDATE vendor_service_requests
    SET status = 'completed', updated_at = NOW()
    WHERE id = p_request_id;

  END IF;
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- Index for customer catalog queries on custom services
-- ────────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_vsr_customer_catalog
  ON vendor_service_requests(vendor_id, status, request_type)
  WHERE request_type = 'new_service'
    AND status IN ('completed', 'pending_deletion');

-- ────────────────────────────────────────────────────────────────────────────
-- RPC: get_vendor_custom_catalog
-- Returns all active custom services for a vendor (admin panel use).
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_vendor_custom_catalog(p_vendor_id UUID)
RETURNS TABLE (
  id              UUID,
  service_name    TEXT,
  description     TEXT,
  active_price    NUMERIC,
  image_url       TEXT,
  status          TEXT,
  created_at      TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, service_name, description, active_price, image_url, status, created_at, updated_at
  FROM vendor_service_requests
  WHERE vendor_id = p_vendor_id
    AND request_type = 'new_service'
    AND status IN ('completed', 'pending_deletion')
  ORDER BY created_at DESC;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- RPC: search_vendor_custom_services
-- Full-text search across all active custom services (customer discovery).
-- Returns vendor name alongside the service for display.
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION search_vendor_custom_services(p_query TEXT)
RETURNS TABLE (
  id            UUID,
  service_name  TEXT,
  description   TEXT,
  active_price  NUMERIC,
  image_url     TEXT,
  vendor_id     UUID,
  vendor_name   TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    vsr.id,
    vsr.service_name,
    vsr.description,
    vsr.active_price,
    vsr.image_url,
    vsr.vendor_id,
    v.business_name AS vendor_name
  FROM vendor_service_requests vsr
  JOIN vendors v ON v.id = vsr.vendor_id
  WHERE vsr.request_type = 'new_service'
    AND vsr.status = 'completed'
    AND v.is_active = true
    AND (
      vsr.service_name ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY vsr.service_name
  LIMIT 50;
$$;
