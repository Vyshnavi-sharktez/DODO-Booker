-- ── Fix toggle_custom_service_active vendor ownership check ──────────────────
--
-- Migration 20260907000007 checks v_req.vendor_id = auth.uid() to verify the
-- calling vendor owns the service. This was valid before phone-auth because
-- vendor dev-auth tokens embedded vendors.id as the user ID.
--
-- After 20261016000002 (phone auth), auth.uid() = vendors.auth_user_id (the
-- Supabase Auth UUID), NOT vendors.id (the DB row UUID). The old comparison
-- always fails for vendors, causing RAISE EXCEPTION 'Unauthorized' (P0001).
--
-- Fix: join through the vendors table using the same ownership pattern used by
-- all RLS policies added in 20261030000001_vsr_authenticated_policies.sql.
-- ─────────────────────────────────────────────────────────────────────────────

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

  -- Authorisation: active admin OR owning vendor.
  -- auth.uid() = vendors.auth_user_id (Supabase Auth UID, set by phone-auth migration 20261016000002)
  -- v_req.vendor_id = vendors.id (DB row UUID) — these are different fields.
  IF NOT (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE auth_user_id = auth.uid()
        AND is_active = TRUE
    )
    OR EXISTS (
      SELECT 1 FROM vendors
      WHERE id = v_req.vendor_id
        AND auth_user_id = auth.uid()
    )
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
