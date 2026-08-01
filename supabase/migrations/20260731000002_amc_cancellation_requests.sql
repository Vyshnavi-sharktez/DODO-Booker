-- amc_cancellation_requests
-- Tracks each customer-initiated cancellation request as an auditable record
-- with its own status lifecycle: pending → approved | rejected.
-- The amc_contracts.status field drives UI state; this table drives the admin
-- review queue and preserves full audit history even after resolution.

CREATE TABLE IF NOT EXISTS public.amc_cancellation_requests (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id   UUID        NOT NULL REFERENCES public.amc_contracts(id) ON DELETE CASCADE,
  customer_id   UUID        NOT NULL REFERENCES public.customers(id)     ON DELETE CASCADE,
  reason        TEXT        NOT NULL,
  remarks       TEXT,
  status        TEXT        NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_amc_cancel_req_contract
  ON public.amc_cancellation_requests (contract_id);

CREATE INDEX IF NOT EXISTS idx_amc_cancel_req_status
  ON public.amc_cancellation_requests (status, created_at);

ALTER TABLE public.amc_cancellation_requests ENABLE ROW LEVEL SECURITY;

-- Customers can insert their own requests.
-- customer_id is set by the app layer; EXISTS confirms it's a real customer.
CREATE POLICY "anon_insert_amc_cancellation_requests"
  ON public.amc_cancellation_requests
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.customers WHERE id = customer_id)
  );

-- Customers can view their own requests.
-- The EXISTS predicate is satisfied by any valid customer row, so the admin
-- panel (which uses the anon key) can also read all rows — matching the
-- pattern used for amc_scheduling_requests.
CREATE POLICY "anon_select_amc_cancellation_requests"
  ON public.amc_cancellation_requests
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (SELECT 1 FROM public.customers WHERE id = customer_id)
  );

-- Admin (anon key) can update status when approving or rejecting.
CREATE POLICY "anon_update_amc_cancellation_requests"
  ON public.amc_cancellation_requests
  FOR UPDATE
  TO anon, authenticated
  USING (true);

-- Service role has unrestricted access.
CREATE POLICY "service_role_all_amc_cancellation_requests"
  ON public.amc_cancellation_requests
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
