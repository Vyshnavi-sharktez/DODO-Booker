-- ── AMC Pause/Resume Feature (base schema) ───────────────────────────────────
-- Customer submits pause request with a required reason.
-- Admin approves or rejects. On approval contract becomes 'paused'.
-- Customer submits resume request. Admin approves, calculates pause duration,
-- and shifts remaining planned_due_dates forward.
--
-- NOTE: pause_start_date is the initial column. It is renamed to pause_started_at
-- (TIMESTAMPTZ) and joined with pause_requested_at / resumed_at in migration 00004.

-- 1. Pause start timestamp on contracts
ALTER TABLE public.amc_contracts
  ADD COLUMN IF NOT EXISTS pause_start_date DATE;

-- 2. Pause requests — reason required, no date columns
CREATE TABLE IF NOT EXISTS public.amc_pause_requests (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  amc_contract_id UUID        NOT NULL REFERENCES public.amc_contracts(id) ON DELETE CASCADE,
  customer_id     TEXT        NOT NULL,
  reason          TEXT        NOT NULL,
  status          TEXT        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at     TIMESTAMPTZ
);

-- 3. Resume requests — pause_duration_days filled on admin approval
CREATE TABLE IF NOT EXISTS public.amc_resume_requests (
  id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  amc_contract_id     UUID        NOT NULL REFERENCES public.amc_contracts(id) ON DELETE CASCADE,
  customer_id         TEXT        NOT NULL,
  reason              TEXT,
  status              TEXT        NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  pause_duration_days INT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at         TIMESTAMPTZ
);

-- 4. RLS — anon key (customer app)
ALTER TABLE public.amc_pause_requests   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amc_resume_requests  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "amc_pause_requests_anon_insert"  ON public.amc_pause_requests  FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "amc_pause_requests_anon_select"  ON public.amc_pause_requests  FOR SELECT TO anon USING (true);
CREATE POLICY "amc_pause_requests_anon_update"  ON public.amc_pause_requests  FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY "amc_resume_requests_anon_insert" ON public.amc_resume_requests FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "amc_resume_requests_anon_select" ON public.amc_resume_requests FOR SELECT TO anon USING (true);
CREATE POLICY "amc_resume_requests_anon_update" ON public.amc_resume_requests FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- 5. Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.amc_pause_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE public.amc_resume_requests;
