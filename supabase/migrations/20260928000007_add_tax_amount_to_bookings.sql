-- Add tax_amount to bookings so the applied tax is persisted at booking creation time.
-- This fixes the GST inconsistency between Checkout and Booking Details.
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS tax_amount NUMERIC(12, 2);

-- Backfill existing bookings where no surge fee or preferred vendor fee was applied.
-- Formula: tax = total_amount - subtotal + discount_amount (discount was subtracted from total).
-- Bookings with surge or preferred vendor fee are left NULL (shown as GST ₹0 in UI).
UPDATE public.bookings
SET tax_amount = GREATEST(0, total_amount - subtotal + COALESCE(discount_amount, 0))
WHERE tax_amount IS NULL
  AND subtotal > 0
  AND total_amount > 0
  AND COALESCE(preferred_vendor_fee_amount, 0) = 0
  AND COALESCE(surge_fee_amount, 0) = 0;
