-- ── price_change: add new_service_name field ─────────────────────────────────
--
-- Vendors can now request both a price change and a service name change in one
-- request. new_service_name stores the proposed name (NULL = no name change).
-- admin_accept_service_request is updated to write service_name when present.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS new_service_name TEXT;

-- ── Recreate admin_accept_service_request ─────────────────────────────────────
-- Previous version: 20260927000004_fix_admin_rpc_active_guards.sql
-- Only the price_change branch changes; all other branches are identical.

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
        SET status = 'deleted', is_active = FALSE, updated_at = NOW()
        WHERE id = p_request_id;
    ELSE
      UPDATE vendor_service_requests
        SET status       = 'completed',
            active_price = price,
            is_active    = EXISTS (
              SELECT 1 FROM public.vendors
              WHERE id = v_req.vendor_id
                AND is_active = TRUE
            ),
            updated_at   = NOW()
        WHERE id = p_request_id;
    END IF;

  -- ── price_change ────────────────────────────────────────────────────────────
  ELSIF v_req.request_type = 'price_change' THEN

    UPDATE vendor_service_requests
      SET price        = COALESCE(v_req.new_price, price),
          active_price = COALESCE(v_req.new_price, active_price),
          service_name = COALESCE(v_req.new_service_name, service_name),
          updated_at   = NOW()
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
