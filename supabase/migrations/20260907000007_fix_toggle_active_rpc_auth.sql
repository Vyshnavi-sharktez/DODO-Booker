-- ── Fix toggle_custom_service_active authorization check ─────────────────────
--
-- Migration 20260907000006 used admin_users.id = auth.uid() but admin_users.id
-- is the surrogate PK. The correct column is auth_user_id, matching the pattern
-- established in 20260904000003 (admin_accept_service_request fix) and
-- 20260902000003 (vsr policy fix).

CREATE OR REPLACE FUNCTION toggle_custom_service_active(
  p_request_id UUID,
  p_is_active   BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req vendor_service_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_req
  FROM vendor_service_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Custom service not found';
  END IF;

  -- Must be a live custom service (new_service + completed or pending_deletion)
  IF v_req.request_type != 'new_service'
     OR v_req.status NOT IN ('completed', 'pending_deletion') THEN
    RAISE EXCEPTION 'Not an active custom service';
  END IF;

  -- Authorisation: active admin OR owning vendor
  IF NOT (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE auth_user_id = auth.uid()
        AND is_active = TRUE
    )
    OR v_req.vendor_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE vendor_service_requests
  SET    is_active  = p_is_active,
         updated_at = NOW()
  WHERE  id = p_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION toggle_custom_service_active(UUID, BOOLEAN) TO authenticated;
