-- Extends amc_cancellation_requests to support two types of cancellation:
--   'membership' — cancels the full AMC contract (existing behaviour)
--   'visit'      — cancels a single visit booking, contract stays active
--
-- reason is made nullable because visit cancellations do not require one.
-- booking_id is populated only for type = 'visit'.

ALTER TABLE public.amc_cancellation_requests
  ALTER COLUMN reason DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'membership'
    CHECK (type IN ('visit', 'membership')),
  ADD COLUMN IF NOT EXISTS booking_id UUID
    REFERENCES public.bookings(id) ON DELETE SET NULL;

-- Existing rows are membership requests (already handled by DEFAULT 'membership').

CREATE INDEX IF NOT EXISTS idx_amc_cancel_req_type
  ON public.amc_cancellation_requests (type, status);
