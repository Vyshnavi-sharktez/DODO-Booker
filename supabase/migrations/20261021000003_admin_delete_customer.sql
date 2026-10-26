-- ─────────────────────────────────────────────────────────────────────────────
-- Customer Deletion: Fix FK violations + safe-delete RPC
--
-- Root cause: cart_items.customer_id and customer_addresses.customer_id
-- reference customers(id) without ON DELETE CASCADE, causing FK violations
-- when deleting a customer who has cart items or saved addresses but no bookings.
--
-- Fix:
--   1. Re-create cart_items.customer_id FK with ON DELETE CASCADE
--   2. Re-create customer_addresses.customer_id FK with ON DELETE CASCADE
--   3. Add admin_delete_customer() RPC that checks for business-critical FK
--      records (bookings, refund_requests) before deleting.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. cart_items: drop existing FK on customer_id and re-add with CASCADE ────
DO $$
DECLARE v_c TEXT;
BEGIN
  SELECT tc.constraint_name INTO v_c
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema    = kcu.table_schema
  WHERE tc.table_schema   = 'public'
    AND tc.table_name     = 'cart_items'
    AND kcu.column_name   = 'customer_id'
    AND tc.constraint_type = 'FOREIGN KEY'
  LIMIT 1;
  IF v_c IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.cart_items DROP CONSTRAINT %I', v_c);
  END IF;
END;
$$;

ALTER TABLE public.cart_items
  ADD CONSTRAINT cart_items_customer_id_fkey
  FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;

-- ── 2. customer_addresses: drop existing FK on customer_id and re-add with CASCADE ──
DO $$
DECLARE v_c TEXT; v_del TEXT;
BEGIN
  SELECT tc.constraint_name, rc.delete_rule
    INTO v_c, v_del
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema    = kcu.table_schema
  JOIN information_schema.referential_constraints rc
    ON rc.constraint_name  = tc.constraint_name
   AND rc.constraint_schema = tc.table_schema
  WHERE tc.table_schema    = 'public'
    AND tc.table_name      = 'customer_addresses'
    AND kcu.column_name    = 'customer_id'
    AND tc.constraint_type = 'FOREIGN KEY'
  LIMIT 1;

  IF v_c IS NOT NULL AND (v_del IS DISTINCT FROM 'CASCADE') THEN
    EXECUTE format('ALTER TABLE public.customer_addresses DROP CONSTRAINT %I', v_c);
    ALTER TABLE public.customer_addresses
      ADD CONSTRAINT customer_addresses_customer_id_fkey
      FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;
  ELSIF v_c IS NULL THEN
    -- No FK found at all; add one
    ALTER TABLE public.customer_addresses
      ADD CONSTRAINT customer_addresses_customer_id_fkey
      FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;
  END IF;
END;
$$;

-- ── 3. admin_delete_customer RPC ──────────────────────────────────────────────
-- Verifies no business-critical records exist, cleans up remaining non-cascading
-- dependent rows, then deletes the customer.
--
-- Tables handled by ON DELETE CASCADE (no explicit delete needed here):
--   cart_items, customer_addresses, wishlists, customer_loyalty,
--   loyalty_transactions, support_conversations, amc_contracts

DROP FUNCTION IF EXISTS public.admin_delete_customer(UUID);

CREATE OR REPLACE FUNCTION public.admin_delete_customer(p_customer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  PERFORM fn_assert_active_admin();

  -- Block if booking history exists — preserve historical records
  SELECT COUNT(*) INTO v_count FROM bookings WHERE customer_id = p_customer_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'BLOCKING_BOOKINGS'
      USING DETAIL = 'Customer has booking history. Deactivate instead of deleting.';
  END IF;

  -- Block if refund requests exist
  SELECT COUNT(*) INTO v_count FROM refund_requests WHERE customer_id = p_customer_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'BLOCKING_REFUNDS'
      USING DETAIL = 'Customer has refund requests. Deactivate instead of deleting.';
  END IF;

  -- Clean up records that have no FK to customers (orphaned after deletion)
  DELETE FROM notifications
  WHERE user_type = 'customer' AND user_id = p_customer_id;

  DELETE FROM customer_questions WHERE customer_id = p_customer_id;

  -- Delete the customer row; CASCADE handles cart_items, customer_addresses,
  -- wishlists, customer_loyalty, loyalty_transactions, support_conversations,
  -- amc_contracts (all already ON DELETE CASCADE).
  DELETE FROM customers WHERE id = p_customer_id;

  RETURN jsonb_build_object('success', true, 'customer_id', p_customer_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_customer(UUID) TO authenticated;
