-- ── AMC Pause lifecycle timestamps ────────────────────────────────────────────
-- Replaces pause_start_date DATE on amc_contracts with three TIMESTAMPTZ columns:
--   pause_requested_at  — when customer submitted the pause request (set by trigger)
--   pause_started_at    — when admin approved the pause
--   resumed_at          — when admin approved the resume
--
-- customer_id on amc_pause_requests / amc_resume_requests remains TEXT with no FK.
-- The customer relationship is owned by amc_contracts.customer_id → customers(id).
-- Admin queries join customers through amc_contracts, not directly.
--
-- Also cleans up any leftover columns from original schema drafts.

-- ── 1. Drop legacy columns from amc_contracts ─────────────────────────────────
ALTER TABLE public.amc_contracts DROP COLUMN IF EXISTS pause_start_date;
ALTER TABLE public.amc_contracts DROP COLUMN IF EXISTS pause_end_date;

-- Drop any leftover columns on amc_pause_requests from original drafts
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'amc_pause_requests'
      AND column_name = 'pause_until'
  ) THEN
    ALTER TABLE public.amc_pause_requests DROP COLUMN pause_until;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'amc_pause_requests'
      AND column_name = 'pause_end_date'
  ) THEN
    ALTER TABLE public.amc_pause_requests DROP COLUMN pause_end_date;
  END IF;
END $$;

-- ── 2. Add new lifecycle timestamp columns ────────────────────────────────────
ALTER TABLE public.amc_contracts
  ADD COLUMN IF NOT EXISTS pause_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pause_started_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS resumed_at         TIMESTAMPTZ;

-- ── 3. Trigger: auto-set pause_requested_at when customer submits a pause request
CREATE OR REPLACE FUNCTION public.fn_amc_set_pause_requested_at()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.amc_contracts
    SET pause_requested_at = NOW()
    WHERE id = NEW.amc_contract_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_amc_set_pause_requested_at ON public.amc_pause_requests;
CREATE TRIGGER trg_amc_set_pause_requested_at
  AFTER INSERT ON public.amc_pause_requests
  FOR EACH ROW EXECUTE FUNCTION public.fn_amc_set_pause_requested_at();
