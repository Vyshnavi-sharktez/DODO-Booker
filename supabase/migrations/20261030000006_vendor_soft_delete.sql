-- Vendor deletion: smart hard-delete vs soft-delete.
--
-- Hard delete (no financial/historical records):
--   Removes operational FK-blocked tables first (vendor_documents,
--   vendor_service_areas, vendor_services, vendor_team_members), then deletes
--   the vendor row. Cascade handles the remaining child tables automatically.
--
-- Soft delete (vendor has bookings, payments, wallet activity, etc.):
--   Sets deleted_at, clears auth_user_id (blocks vendor-app login), and
--   deactivates the vendor. Historical rows are preserved intact.
--   The vendor is hidden from all active admin/vendor lists.
--
-- Returns JSONB {action: 'deleted'} or {action: 'archived', reason: '...'}.
--
-- Financial/historical check tables:
--   bookings, customer_reviews, booking_assignments,
--   wallet_transactions, vendor_settlements, withdrawal_requests,
--   vendor_subscription_payments, vendor_wallet_topup_attempts

-- ── 1. Add deleted_at column to vendors ──────────────────────────────────────

ALTER TABLE public.vendors
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

-- ── 2. Replace admin_delete_vendor RPC ────────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_delete_vendor(UUID);

CREATE OR REPLACE FUNCTION public.admin_delete_vendor(p_vendor_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking_count    INTEGER := 0;
  v_review_count     INTEGER := 0;
  v_wallet_tx_count  INTEGER := 0;
  v_settlement_count INTEGER := 0;
  v_sub_pay_count    INTEGER := 0;
  v_topup_count      INTEGER := 0;
  v_reasons          TEXT[]  := '{}';
  v_has_history      BOOLEAN := FALSE;
BEGIN
  PERFORM fn_assert_active_admin();

  IF NOT EXISTS (SELECT 1 FROM vendors WHERE id = p_vendor_id) THEN
    RAISE EXCEPTION 'Vendor % not found', p_vendor_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Count each category of historical/financial records.
  SELECT COUNT(*) INTO v_booking_count
    FROM bookings WHERE vendor_id = p_vendor_id;

  SELECT COUNT(*) INTO v_review_count
    FROM customer_reviews WHERE vendor_id = p_vendor_id;

  SELECT COUNT(*) INTO v_wallet_tx_count
    FROM wallet_transactions WHERE vendor_id = p_vendor_id;

  SELECT COUNT(*) INTO v_settlement_count
    FROM vendor_settlements WHERE vendor_id = p_vendor_id;

  SELECT COUNT(*) INTO v_sub_pay_count
    FROM vendor_subscription_payments WHERE vendor_id = p_vendor_id;

  SELECT COUNT(*) INTO v_topup_count
    FROM vendor_wallet_topup_attempts WHERE vendor_id = p_vendor_id;

  v_has_history :=
    v_booking_count   > 0 OR
    v_review_count    > 0 OR
    v_wallet_tx_count > 0 OR
    v_settlement_count > 0 OR
    v_sub_pay_count   > 0 OR
    v_topup_count     > 0 OR
    EXISTS (SELECT 1 FROM withdrawal_requests WHERE vendor_id = p_vendor_id) OR
    EXISTS (SELECT 1 FROM booking_assignments  WHERE vendor_id = p_vendor_id);

  IF v_has_history THEN
    -- ── Soft delete: preserve all history, block login, hide from lists ──────
    IF v_booking_count > 0 THEN
      v_reasons := array_append(v_reasons,
        v_booking_count || ' booking' || CASE WHEN v_booking_count = 1 THEN '' ELSE 's' END);
    END IF;
    IF v_review_count > 0 THEN
      v_reasons := array_append(v_reasons,
        v_review_count || ' review' || CASE WHEN v_review_count = 1 THEN '' ELSE 's' END);
    END IF;
    IF v_wallet_tx_count > 0 THEN
      v_reasons := array_append(v_reasons,
        v_wallet_tx_count || ' wallet transaction' || CASE WHEN v_wallet_tx_count = 1 THEN '' ELSE 's' END);
    END IF;
    IF v_settlement_count > 0 THEN
      v_reasons := array_append(v_reasons,
        v_settlement_count || ' settlement' || CASE WHEN v_settlement_count = 1 THEN '' ELSE 's' END);
    END IF;
    IF v_sub_pay_count > 0 THEN
      v_reasons := array_append(v_reasons,
        v_sub_pay_count || ' subscription payment' || CASE WHEN v_sub_pay_count = 1 THEN '' ELSE 's' END);
    END IF;
    IF v_topup_count > 0 THEN
      v_reasons := array_append(v_reasons,
        v_topup_count || ' wallet top-up' || CASE WHEN v_topup_count = 1 THEN '' ELSE 's' END);
    END IF;

    UPDATE vendors
    SET deleted_at   = now(),
        is_active    = FALSE,
        status       = 'inactive',
        auth_user_id = NULL
    WHERE id = p_vendor_id;

    RETURN jsonb_build_object(
      'action', 'archived',
      'reason', array_to_string(
        CASE WHEN array_length(v_reasons, 1) > 0 THEN v_reasons ELSE ARRAY['historical records'] END,
        ', '
      )
    );

  ELSE
    -- ── Hard delete: clear NO ACTION FK tables, then delete vendor row ────────
    DELETE FROM vendor_documents    WHERE vendor_id = p_vendor_id;
    DELETE FROM vendor_service_areas WHERE vendor_id = p_vendor_id;
    DELETE FROM vendor_services     WHERE vendor_id = p_vendor_id;
    DELETE FROM vendor_team_members WHERE vendor_id = p_vendor_id;

    DELETE FROM vendors WHERE id = p_vendor_id;

    RETURN jsonb_build_object('action', 'deleted');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_vendor(UUID) TO authenticated;
