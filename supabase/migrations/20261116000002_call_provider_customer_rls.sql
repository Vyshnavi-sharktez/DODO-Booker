-- Migration: 20261116000002_call_provider_customer_rls.sql
--
-- Customer app now shows a "Call Vendor" button on the booking details screen
-- for bookings in accepted/en_route status.  It reads call_provider_configs via
-- callProviderEnabledProvider (StreamProvider) to gate the button.
--
-- The existing policy (20261116000001) only grants SELECT to vendors.
-- This adds an equivalent policy for authenticated customer accounts.

DROP POLICY IF EXISTS "Customers can read call_provider_configs"
  ON public.call_provider_configs;

CREATE POLICY "Customers can read call_provider_configs"
  ON public.call_provider_configs
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.customers
      WHERE auth_user_id = auth.uid()
    )
  );
