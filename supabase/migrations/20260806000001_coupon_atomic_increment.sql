-- Migration: Atomic coupon used_count increment RPC
--
-- Replaces the read-modify-write pattern in CouponService with a single
-- server-side UPDATE. PostgreSQL evaluates `used_count = used_count + 1`
-- atomically: it acquires a row-level lock, reads the current value,
-- increments it, and commits — all in one statement. No concurrent transaction
-- can interleave between the read and the write, eliminating the race condition.

CREATE OR REPLACE FUNCTION increment_coupon_used_count(p_coupon_id UUID)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE coupons
  SET used_count = used_count + 1
  WHERE id = p_coupon_id;
$$;

-- Customers trigger this during booking confirmation. SECURITY DEFINER lets the
-- function perform the UPDATE even though the customer RLS policy only grants
-- SELECT, while keeping write access scoped to exactly this one operation.
GRANT EXECUTE ON FUNCTION increment_coupon_used_count(UUID) TO authenticated;
