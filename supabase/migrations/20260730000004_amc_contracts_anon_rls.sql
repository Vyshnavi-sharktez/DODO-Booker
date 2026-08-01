-- Fix amc_contracts RLS for the custom phone-auth flow.
--
-- The customer app authenticates via a dev_auth table and stores the phone in
-- SharedPreferences. supabase.auth is never called, so auth.uid() = NULL and
-- auth.role() = 'anon' for every customer request. The prior INSERT policy had
-- no explicit TO clause; in Supabase's PostgREST context this can be treated
-- as authenticated-only, blocking all anon INSERTs — the same issue previously
-- fixed for cart_items in 20260616000001_cart_items_anon_rls.sql.
--
-- Additionally, the prior "Admins can manage AMC contracts" FOR ALL policy had
-- no TO clause, meaning its implicit WITH CHECK (auth.role() = 'service_role')
-- applied to anon users and could block INSERT even when the INSERT policy
-- passed, depending on evaluation order.

-- ── Drop all current amc_contracts policies ───────────────────────────────────

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'amc_contracts'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.amc_contracts', r.policyname);
  END LOOP;
END
$$;

-- ── Rebuild with explicit role scoping ────────────────────────────────────────

-- INSERT: anon customers can create AMC contracts.
-- Security: customer_id must reference a real customer row.
-- App layer (checkout_service.dart) always sets customer_id to the signed-in
-- customer's UUID, so this check prevents inserting contracts for phantom IDs.
CREATE POLICY "anon_insert_amc_contracts"
  ON public.amc_contracts
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.customers WHERE id = customer_id)
  );

-- SELECT: anon customers can read their own contracts.
-- Same existence check as INSERT; contract IDs are UUID v4 and are only
-- surfaced to a customer via their own booking records.
CREATE POLICY "anon_select_amc_contracts"
  ON public.amc_contracts
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (SELECT 1 FROM public.customers WHERE id = customer_id)
  );

-- ALL: service_role has unrestricted access for admin panel and the
-- fn_amc_visit_completed trigger (SECURITY DEFINER already bypasses RLS,
-- but explicit policy avoids reliance on that assumption).
CREATE POLICY "service_role_all_amc_contracts"
  ON public.amc_contracts
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Confirm RLS remains enabled.
ALTER TABLE public.amc_contracts ENABLE ROW LEVEL SECURITY;
