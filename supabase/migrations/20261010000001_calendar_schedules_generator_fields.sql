-- Add slot generator config columns to calendar_schedules
-- Mirrors the generator fields in global/service scheduling config
ALTER TABLE calendar_schedules
  ADD COLUMN IF NOT EXISTS slot_start_time       TEXT,
  ADD COLUMN IF NOT EXISTS slot_end_time         TEXT,
  ADD COLUMN IF NOT EXISTS slot_interval_hours   INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS slot_interval_minutes INT NOT NULL DEFAULT 30;
