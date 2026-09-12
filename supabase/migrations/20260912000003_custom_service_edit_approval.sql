-- Allow vendors to propose edits to approved custom services.
-- edit_service rows are pending proposals; approval merges them into the parent row.

-- 1. Add 'edit_service' to request_type CHECK constraint.
--    The live constraint is named vsr_request_type_check (defined in 20260904000002).
ALTER TABLE public.vendor_service_requests
  DROP CONSTRAINT IF EXISTS vsr_request_type_check;

ALTER TABLE public.vendor_service_requests
  ADD CONSTRAINT vsr_request_type_check
  CHECK (request_type IN (
    'new_service', 'price_change', 'delete_service', 'edit_service'
  ));

-- 2. Update admin_accept_service_request to handle edit_service proposals.
--    When approved: copy content/warranty from proposal to parent row,
--    re-link service_attributes from proposal to parent.

CREATE OR REPLACE FUNCTION public.admin_accept_service_request(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
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

  -- ── new_service ────────────────────────────────────────────────────────────
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

  -- ── price_change ───────────────────────────────────────────────────────────
  ELSIF v_req.request_type = 'price_change' THEN

    UPDATE vendor_service_requests
      SET price = v_req.new_price, active_price = v_req.new_price, updated_at = NOW()
      WHERE id = v_req.parent_request_id;

    UPDATE vendor_service_requests
      SET status = 'completed', updated_at = NOW()
      WHERE id = p_request_id;

  -- ── delete_service (legacy) ────────────────────────────────────────────────
  ELSIF v_req.request_type = 'delete_service' THEN

    UPDATE vendor_service_requests
      SET status = 'deleted', updated_at = NOW()
      WHERE id = v_req.parent_request_id;

    UPDATE vendor_service_requests
      SET status = 'completed', updated_at = NOW()
      WHERE id = p_request_id;

  -- ── edit_service: apply proposal to parent, re-link attributes ─────────────
  ELSIF v_req.request_type = 'edit_service' THEN

    -- Merge vendor-editable fields from proposal into the live service row.
    -- Deliberately excludes service_name, description, active_price, image_url
    -- (those remain admin-controlled via CustomServiceEditDialog).
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

    -- Replace parent's attributes with the proposal's copy.
    DELETE FROM service_attributes
      WHERE custom_service_id = v_req.parent_request_id;

    UPDATE service_attributes
      SET custom_service_id = v_req.parent_request_id
      WHERE custom_service_id = p_request_id;

    -- Mark proposal completed (kept for audit history).
    UPDATE vendor_service_requests
      SET status = 'completed', updated_at = NOW()
      WHERE id = p_request_id;

  END IF;
END;
$$;

-- 3. Update admin_reject_service_request to clean up edit_service proposal attributes.

CREATE OR REPLACE FUNCTION public.admin_reject_service_request(
  p_request_id UUID,
  p_reason     TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_req RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO v_req FROM vendor_service_requests WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Service request % not found', p_request_id;
  END IF;

  IF v_req.status = 'pending_deletion' THEN
    UPDATE vendor_service_requests
      SET status = 'completed', rejection_reason = NULLIF(TRIM(p_reason), '')
      WHERE id = p_request_id;

  ELSIF v_req.request_type = 'edit_service' THEN
    -- Clean up orphaned attributes on the rejected proposal.
    DELETE FROM service_attributes WHERE custom_service_id = p_request_id;
    UPDATE vendor_service_requests
      SET status = 'rejected', rejection_reason = NULLIF(TRIM(p_reason), '')
      WHERE id = p_request_id;

  ELSE
    UPDATE vendor_service_requests
      SET status = 'rejected', rejection_reason = NULLIF(TRIM(p_reason), '')
      WHERE id = p_request_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_accept_service_request(UUID)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_service_request(UUID, TEXT) TO authenticated;
