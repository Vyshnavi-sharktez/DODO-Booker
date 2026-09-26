-- ─────────────────────────────────────────────────────────────────────────────
-- Fix Missing is_active Guards in Admin RPCs
--
-- Several SECURITY DEFINER functions accepted calls from any authenticated
-- Supabase user (or any admin, including deactivated ones).  This migration
-- adds the missing AND is_active = TRUE check to all affected functions.
--
-- Functions fixed here (most-recent version of each as of 20260912000003):
--
--   1. admin_accept_service_request — had NO admin_users check at all in its
--      most recent version (20260912000003).  Any authenticated Supabase user
--      could call it.  Now requires active admin.
--
--   2. admin_reject_service_request — checked auth_user_id = auth.uid() but
--      did not verify is_active = TRUE.  A deactivated admin with a live JWT
--      could still reject service requests.
--
-- All other admin-callable SECURITY DEFINER functions either already include
-- AND is_active = TRUE (toggle_custom_service_active, support RPCs, all refund
-- RPCs via fn_assert_active_admin), or are vendor-callable and do not need it.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. admin_accept_service_request ──────────────────────────────────────────
-- Last defined in 20260912000003.  Replaces the entire function to add the
-- active-admin guard at the top.  Business logic is unchanged.

CREATE OR REPLACE FUNCTION public.admin_accept_service_request(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req  vendor_service_requests%ROWTYPE;
BEGIN
  -- Active-admin guard
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE auth_user_id = auth.uid()
      AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Unauthorized: caller is not an active admin'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_req
  FROM vendor_service_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found: %', p_request_id;
  END IF;

  -- ── new_service ─────────────────────────────────────────────────────────────
  IF v_req.request_type = 'new_service' THEN

    IF v_req.status = 'pending_deletion' THEN
      UPDATE vendor_service_requests
        SET status = 'deleted', updated_at = NOW()
        WHERE id = p_request_id;
    ELSE
      UPDATE vendor_service_requests
        SET status = 'completed', active_price = price, updated_at = NOW()
        WHERE id = p_request_id;
    END IF;

  -- ── price_change ────────────────────────────────────────────────────────────
  ELSIF v_req.request_type = 'price_change' THEN

    UPDATE vendor_service_requests
      SET price = v_req.new_price, active_price = v_req.new_price, updated_at = NOW()
      WHERE id = v_req.parent_request_id;

    UPDATE vendor_service_requests
      SET status = 'completed', updated_at = NOW()
      WHERE id = p_request_id;

  -- ── delete_service (legacy rows) ────────────────────────────────────────────
  ELSIF v_req.request_type = 'delete_service' THEN

    UPDATE vendor_service_requests
      SET status = 'deleted', updated_at = NOW()
      WHERE id = v_req.parent_request_id;

    UPDATE vendor_service_requests
      SET status = 'completed', updated_at = NOW()
      WHERE id = p_request_id;

  -- ── edit_service ────────────────────────────────────────────────────────────
  ELSIF v_req.request_type = 'edit_service' THEN

    UPDATE vendor_service_requests
      SET included_items      = v_req.included_items,
          excluded_items      = v_req.excluded_items,
          before_after_pairs  = v_req.before_after_pairs,
          warranty_enabled    = v_req.warranty_enabled,
          warranty_days       = v_req.warranty_days,
          warranty_covers     = v_req.warranty_covers,
          warranty_exclusions = v_req.warranty_exclusions,
          updated_at          = NOW()
      WHERE id = v_req.parent_request_id;

    DELETE FROM service_attributes
      WHERE custom_service_id = v_req.parent_request_id;

    UPDATE service_attributes
      SET custom_service_id = v_req.parent_request_id
      WHERE custom_service_id = p_request_id;

    UPDATE vendor_service_requests
      SET status = 'completed', updated_at = NOW()
      WHERE id = p_request_id;

  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_accept_service_request(UUID) TO authenticated;


-- ── 2. admin_reject_service_request ──────────────────────────────────────────
-- Last defined in 20260912000003.  Adds AND is_active = TRUE to the guard.
-- Business logic is unchanged.

CREATE OR REPLACE FUNCTION public.admin_reject_service_request(
  p_request_id UUID,
  p_reason     TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req RECORD;
BEGIN
  -- Active-admin guard
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE auth_user_id = auth.uid()
      AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Unauthorized: caller is not an active admin'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_req FROM vendor_service_requests WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Service request % not found', p_request_id;
  END IF;

  IF v_req.status = 'pending_deletion' THEN
    UPDATE vendor_service_requests
      SET status = 'completed',
          rejection_reason = NULLIF(TRIM(p_reason), ''),
          updated_at = NOW()
      WHERE id = p_request_id;

  ELSIF v_req.request_type = 'edit_service' THEN
    DELETE FROM service_attributes WHERE custom_service_id = p_request_id;
    UPDATE vendor_service_requests
      SET status = 'rejected',
          rejection_reason = NULLIF(TRIM(p_reason), ''),
          updated_at = NOW()
      WHERE id = p_request_id;

  ELSE
    UPDATE vendor_service_requests
      SET status = 'rejected',
          rejection_reason = NULLIF(TRIM(p_reason), ''),
          updated_at = NOW()
      WHERE id = p_request_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reject_service_request(UUID, TEXT) TO authenticated;
