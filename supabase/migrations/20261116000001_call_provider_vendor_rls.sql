-- Migration: 20261116000001_call_provider_vendor_rls.sql
--
-- Root cause: call_provider_configs had only an admin-only FOR ALL policy.
-- Vendor app authenticates as `authenticated` role (not admin), so the Supabase
-- .stream() call returned zero rows, causing callProviderEnabledProvider to
-- always emit false and hiding the Call Customer button regardless of config.
--
-- Fix 1: Add a vendor-scoped SELECT policy using the established
--   vendors.auth_user_id = auth.uid() identity pattern.
--   Customers (customers table, not vendors) remain excluded.
--   Admins retain full access via the existing FOR ALL policy.
--
-- Fix 2: Add call_provider_configs to the supabase_realtime publication so
--   admin toggles propagate live to open vendor app sessions without restart.

-- ── 1. Vendor SELECT policy ───────────────────────────────────────────────────
DROP POLICY IF EXISTS "Vendors can read call_provider_configs"
  ON public.call_provider_configs;

CREATE POLICY "Vendors can read call_provider_configs"
  ON public.call_provider_configs
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.vendors
      WHERE auth_user_id = auth.uid()
    )
  );

-- ── 2. Enable Realtime on call_provider_configs ───────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'call_provider_configs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.call_provider_configs;
  END IF;
END $$;
