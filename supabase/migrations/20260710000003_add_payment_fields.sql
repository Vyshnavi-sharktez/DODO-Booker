-- Add payment_method and payment_status to bookings.
-- Defaults keep existing rows valid: cash / pending matches the Customer App's
-- initial "Cash After Service" option and pre-payment booking state.

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'cash',
  ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'pending';
