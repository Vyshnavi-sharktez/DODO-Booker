-- ============================================================
-- Coupon: add 'all_customers' to customer_eligibility check
-- ============================================================
-- The form uses three values:
--   'all_customers' → open to everyone, no restrictions
--   'all'           → Max Order Wise (requires min completed orders)
--   'selected'      → Customer ID Based
-- The original constraint only allowed 'all' and 'selected'.
-- This migration expands it and backfills existing 'all' rows
-- that have no max_order_wise_limit to 'all_customers'.
-- ============================================================

-- ── 1. Drop old constraint ────────────────────────────────────────────────────

ALTER TABLE public.coupons
  DROP CONSTRAINT IF EXISTS coupons_customer_eligibility_check;

-- ── 2. Add expanded constraint ────────────────────────────────────────────────

ALTER TABLE public.coupons
  ADD CONSTRAINT coupons_customer_eligibility_check
  CHECK (customer_eligibility IN ('all', 'all_customers', 'selected'));

-- ── 3. Backfill: 'all' with no order limit → 'all_customers' ─────────────────
-- These coupons were created before the rename and are semantically
-- "open to all customers with no extra restrictions".

UPDATE public.coupons
SET customer_eligibility = 'all_customers'
WHERE customer_eligibility = 'all'
  AND max_order_wise_limit IS NULL;
