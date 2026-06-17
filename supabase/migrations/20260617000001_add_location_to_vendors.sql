-- Add latitude and longitude columns to vendors table.
-- Both are nullable so existing rows are unaffected.
ALTER TABLE vendors
  ADD COLUMN IF NOT EXISTS latitude  NUMERIC(10,7),
  ADD COLUMN IF NOT EXISTS longitude NUMERIC(10,7);
