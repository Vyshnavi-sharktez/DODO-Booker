-- Add slot tracking columns to bookings for dynamic capacity counting.
-- scheduled_time stores the slot label ("07:00 AM") used at booking time.
-- service_id denormalises the booked service for fast per-slot counts.

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS scheduled_time TEXT,
  ADD COLUMN IF NOT EXISTS service_id     UUID;

CREATE INDEX IF NOT EXISTS idx_bookings_service_date_slot
  ON bookings (service_id, service_date, scheduled_time)
  WHERE scheduled_time IS NOT NULL;
