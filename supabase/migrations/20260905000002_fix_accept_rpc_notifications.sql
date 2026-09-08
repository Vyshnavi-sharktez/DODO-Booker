-- Fix: remove bogus INSERT INTO vendor_notifications blocks from
-- admin_accept_service_request.  The table does not exist; notifications are
-- handled automatically by fn_notify_vendor_service_request_status which fires
-- on every status UPDATE to vendor_service_requests.
-- Status-update logic is unchanged.

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
      UPDATE vendor_service_requests
      SET status = 'deleted', updated_at = NOW()
      WHERE id = p_request_id;

    ELSE
      UPDATE vendor_service_requests
      SET status      = 'completed',
          active_price = price,
          updated_at  = NOW()
      WHERE id = p_request_id;
    END IF;

  -- ── price_change ─────────────────────────────────────────────────────────
  ELSIF v_req.request_type = 'price_change' THEN

    UPDATE vendor_service_requests
    SET price        = v_req.new_price,
        active_price = v_req.new_price,
        updated_at   = NOW()
    WHERE id = v_req.parent_request_id;

    UPDATE vendor_service_requests
    SET status = 'completed', updated_at = NOW()
    WHERE id = p_request_id;

  -- ── delete_service (legacy row-type) ─────────────────────────────────────
  ELSIF v_req.request_type = 'delete_service' THEN

    UPDATE vendor_service_requests
    SET status = 'deleted', updated_at = NOW()
    WHERE id = v_req.parent_request_id;

    UPDATE vendor_service_requests
    SET status = 'completed', updated_at = NOW()
    WHERE id = p_request_id;

  END IF;
END;
$$;
