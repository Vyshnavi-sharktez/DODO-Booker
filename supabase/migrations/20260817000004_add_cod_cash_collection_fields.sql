-- Add COD cash collection confirmation fields to bookings table.
-- Used to record vendor confirmation on whether cash was collected for COD bookings.

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS cod_cash_collected BOOLEAN,
  ADD COLUMN IF NOT EXISTS cod_not_collected_reason TEXT,
  ADD COLUMN IF NOT EXISTS cod_confirmed_at TIMESTAMPTZ;
