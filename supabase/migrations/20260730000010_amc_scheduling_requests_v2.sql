-- Add preferred_date so customers can specify when they'd like the next visit.
ALTER TABLE amc_scheduling_requests
  ADD COLUMN IF NOT EXISTS preferred_date date;

-- Extend status to include 'rejected' (admin can reject a request;
-- customer is then free to submit a new one).
ALTER TABLE amc_scheduling_requests
  DROP CONSTRAINT IF EXISTS amc_scheduling_requests_status_check;

ALTER TABLE amc_scheduling_requests
  ADD CONSTRAINT amc_scheduling_requests_status_check
  CHECK (status IN ('pending', 'scheduled', 'cancelled', 'rejected'));
