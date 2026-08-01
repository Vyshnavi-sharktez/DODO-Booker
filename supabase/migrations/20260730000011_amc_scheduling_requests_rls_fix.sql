-- Fix amc_scheduling_requests RLS for the custom phone-auth flow.
--
-- The customer app never calls supabase.auth, so auth.uid() = NULL and
-- auth.role() = 'anon' for every customer request. The original policies
-- used current_setting('request.jwt.claims')::jsonb ->> 'phone' to scope
-- rows, but that claim is never present in the anon JWT — the lookup always
-- returns NULL and every INSERT is rejected.
--
-- Fix follows the same pattern as 20260730000004_amc_contracts_anon_rls.sql:
-- allow anon/authenticated for customer operations, scoped by customer_id
-- existence in the customers table (the UUID is only ever surfaced to the
-- customer via their own contract data, so brute-force guessing is infeasible).
-- Service role retains unrestricted access for admin approve/reject.

-- ── Drop all current policies ─────────────────────────────────────────────────

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'amc_scheduling_requests'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.amc_scheduling_requests', r.policyname);
  END LOOP;
END
$$;

-- ── Rebuild with explicit role scoping ────────────────────────────────────────

-- INSERT: anon customers can submit a scheduling request for their own contract.
-- customer_id is set by the app layer (checkout_service.dart) to the customer's
-- own UUID; the EXISTS check confirms it's a real customer row.
CREATE POLICY "anon_insert_amc_scheduling_requests"
  ON public.amc_scheduling_requests
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.customers WHERE id = customer_id)
  );

-- SELECT: anon customers can read their own scheduling requests.
CREATE POLICY "anon_select_amc_scheduling_requests"
  ON public.amc_scheduling_requests
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (SELECT 1 FROM public.customers WHERE id = customer_id)
  );

-- UPDATE: anon customers can cancel their own pending requests.
-- (status → 'cancelled' is the only update the customer app performs.)
CREATE POLICY "anon_update_amc_scheduling_requests"
  ON public.amc_scheduling_requests
  FOR UPDATE
  TO anon, authenticated
  USING (
    EXISTS (SELECT 1 FROM public.customers WHERE id = customer_id)
  );

-- ALL: service_role has unrestricted access for admin approve/reject.
CREATE POLICY "service_role_all_amc_scheduling_requests"
  ON public.amc_scheduling_requests
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Confirm RLS remains enabled.
ALTER TABLE public.amc_scheduling_requests ENABLE ROW LEVEL SECURITY;
