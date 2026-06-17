-- Add latitude and longitude columns to bookings table.
-- Both are nullable so existing rows are unaffected.
-- Coordinates are snapshotted at booking creation time and are
-- independent of the customer_addresses row.
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS latitude  NUMERIC(10,7),
  ADD COLUMN IF NOT EXISTS longitude NUMERIC(10,7);
