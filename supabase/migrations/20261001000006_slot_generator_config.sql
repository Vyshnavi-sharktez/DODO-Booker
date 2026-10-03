-- Add slot generator configuration columns to service_scheduling and
-- global_scheduling so the admin configures start time, end time, and
-- interval rather than adding individual slots manually.
--
-- The TEXT[] slots column is kept as the materialized generated output —
-- the customer app continues to read it unchanged.  These four new columns
-- simply preserve the generator inputs so the admin can re-open the dialog
-- and see (and edit) the same values they previously set.

ALTER TABLE service_scheduling
  ADD COLUMN IF NOT EXISTS slot_start_time       TEXT,
  ADD COLUMN IF NOT EXISTS slot_end_time         TEXT,
  ADD COLUMN IF NOT EXISTS slot_interval_hours   INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS slot_interval_minutes INTEGER NOT NULL DEFAULT 30;

ALTER TABLE global_scheduling
  ADD COLUMN IF NOT EXISTS slot_start_time       TEXT,
  ADD COLUMN IF NOT EXISTS slot_end_time         TEXT,
  ADD COLUMN IF NOT EXISTS slot_interval_hours   INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS slot_interval_minutes INTEGER NOT NULL DEFAULT 30;
