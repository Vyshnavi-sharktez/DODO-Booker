-- Back-fill tax_amount for all bookings where it was not persisted at creation time.
--
-- The original migration (20260928000007) only covered bookings with no surge fee
-- and no preferred-vendor fee. This migration covers the remaining cases.
--
-- Formula derived from createCartBooking / createBooking in the Dart services:
--   total_amount = subtotal + tax + surge_fee_amount + preferred_vendor_fee_amount - discount_amount
--   ∴ tax = total_amount - subtotal + discount_amount - surge_fee_amount - preferred_vendor_fee_amount
--
-- Only updates rows where tax_amount IS NULL (not previously back-filled) and the
-- derived tax value is > 0 (meaning GST was actually charged).

UPDATE public.bookings
SET tax_amount = GREATEST(
  0,
  total_amount
    - subtotal
    + COALESCE(discount_amount, 0)
    - COALESCE(surge_fee_amount, 0)
    - COALESCE(preferred_vendor_fee_amount, 0)
)
WHERE tax_amount IS NULL
  AND subtotal > 0
  AND total_amount > 0
  AND (
    total_amount - subtotal
    + COALESCE(discount_amount, 0)
    - COALESCE(surge_fee_amount, 0)
    - COALESCE(preferred_vendor_fee_amount, 0)
  ) > 0;
