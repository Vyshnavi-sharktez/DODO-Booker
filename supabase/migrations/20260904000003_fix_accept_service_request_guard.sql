-- Fix admin_accept_service_request: guard was checking admin_users.id = auth.uid()
-- but admin_users.id is the surrogate PK; auth.uid() matches auth_user_id.
-- Replace only the guard line; everything else is unchanged.

CREATE OR REPLACE FUNCTION admin_accept_service_request(p_request_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_req RECORD;
BEGIN
  -- Admin-only guard
  IF NOT EXISTS (
    SELECT 1
    FROM admin_users
    WHERE auth_user_id = auth.uid()
  ) THEN
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
