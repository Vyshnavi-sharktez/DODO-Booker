-- Add per-vendor commission rate (%). Defaults to 0 = no commission deducted.
-- Used in settlement calculations: vendor receives grossEarnings * (1 - commission_rate/100).

ALTER TABLE vendors
  ADD COLUMN IF NOT EXISTS commission_rate NUMERIC(5,2) NOT NULL DEFAULT 0
    CHECK (commission_rate >= 0 AND commission_rate < 100);
