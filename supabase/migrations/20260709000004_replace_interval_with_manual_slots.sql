-- Replace interval-based scheduling with explicit per-service slot list.
-- Drop the generated-slot columns and add a TEXT[] column for manual slots.
-- Format: each element is a 12-hour label like "09:00 AM" or "11:30 AM".

ALTER TABLE service_scheduling
  DROP COLUMN IF EXISTS start_time,
  DROP COLUMN IF EXISTS end_time,
  DROP COLUMN IF EXISTS slot_interval_minutes,
  ADD COLUMN IF NOT EXISTS slots TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
