-- Add cancellation timestamp to bookings table
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
