-- Replace the blanket DELETE RLS policy with a SECURITY DEFINER RPC that
-- enforces ownership and pending-status checks inside the database function.

-- Drop the policy that allowed direct table deletes.
DROP POLICY IF EXISTS "vsr_vendor_delete_pending" ON vendor_service_requests;

-- Secure delete RPC: deletes only when id + vendor_id match and status = pending.
CREATE OR REPLACE FUNCTION delete_vendor_service_request(
  p_request_id UUID,
  p_vendor_id  UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  DELETE FROM vendor_service_requests
  WHERE id        = p_request_id
    AND vendor_id = p_vendor_id
    AND status    = 'pending';

  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count = 0 THEN
    RAISE EXCEPTION 'No pending request found for this vendor'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_vendor_service_request(UUID, UUID) TO anon, authenticated;
