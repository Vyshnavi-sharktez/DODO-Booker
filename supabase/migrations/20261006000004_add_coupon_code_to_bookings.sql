-- Add coupon_code to bookings so the applied coupon is visible in booking history.
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS coupon_code TEXT;
