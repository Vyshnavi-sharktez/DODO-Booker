-- Grants the admin panel (anon key) permission to UPDATE amc_contracts.
--
-- Root cause: the existing UPDATE policy ("Customers can update own AMC contract
-- cancellation") uses a phone-claim check that only matches authenticated customers.
-- The admin panel authenticates with the anon key (no phone claim in the JWT), so
-- every UPDATE amc_contracts call from the admin panel silently returns 0 rows with
-- no error.  This caused approved membership cancellations to leave amc_contracts
-- stuck at status='active'.
--
-- Fix: add a permissive UPDATE policy for the anon role, matching the pattern used
-- on amc_cancellation_requests (which has "anon_update_amc_cancellation_requests").

CREATE POLICY "anon_update_amc_contracts"
  ON public.amc_contracts
  FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);
