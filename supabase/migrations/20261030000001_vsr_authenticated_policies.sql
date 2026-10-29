-- ── vendor_service_requests: authenticated-role policies for phone-auth vendors ─
--
-- Context
-- ───────
-- Migration 20261016000002_phone_auth_migration switched the vendor app from
-- anonymous Supabase calls to real Supabase Phone OTP auth.  After that change,
-- vendor app requests run as the `authenticated` role, not `anon`.
--
-- Migration 20260902000002_fix_vsr_anon_rls had already dropped the original
-- `authenticated` INSERT/SELECT policies and replaced them with `anon` policies,
-- because at that time the vendor app had no Supabase auth session.
--
-- As a result there are currently NO INSERT, SELECT, or UPDATE policies for the
-- `authenticated` role that cover ordinary vendors (only the admin SELECT/UPDATE
-- policies exist for authenticated users).  Every INSERT from the vendor app
-- therefore hits the RLS block and throws:
--   PostgresException: new row violates row-level security policy
--   for table "vendor_service_requests", code: 42501
--
-- Fix
-- ───
-- Add three policies for the `authenticated` role, each scoped to the vendor
-- who owns the row via the `vendors.auth_user_id` linkage column added in
-- 20261016000002.  The `anon` policies are preserved so that any vendor-app
-- clients that pre-date the phone-auth migration continue to work.
--
-- Policy expressions
-- ──────────────────
--   vendor_id  → vendors.id   (the UUID of the vendor row)
--   auth.uid() → auth user ID (set by Supabase after phone OTP verification)
--   vendors.auth_user_id links the two, set by ensure_vendor_created() on login.
-- ─────────────────────────────────────────────────────────────────────────────

-- INSERT: an authenticated vendor may create rows only for their own vendor account.
DROP POLICY IF EXISTS "vsr_vendor_insert_authenticated" ON vendor_service_requests;
CREATE POLICY "vsr_vendor_insert_authenticated" ON vendor_service_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM vendors
      WHERE id = vendor_id
        AND auth_user_id = auth.uid()
    )
  );

-- SELECT: an authenticated vendor may read their own rows.
-- (Admins are already covered by the existing vsr_admin_select policy.)
DROP POLICY IF EXISTS "vsr_vendor_select_authenticated" ON vendor_service_requests;
CREATE POLICY "vsr_vendor_select_authenticated" ON vendor_service_requests
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM vendors
      WHERE id = vendor_id
        AND auth_user_id = auth.uid()
    )
  );

-- UPDATE: an authenticated vendor may update their own rows.
-- (Admins are already covered by the existing vsr_admin_update policy.)
DROP POLICY IF EXISTS "vsr_vendor_update_authenticated" ON vendor_service_requests;
CREATE POLICY "vsr_vendor_update_authenticated" ON vendor_service_requests
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM vendors
      WHERE id = vendor_id
        AND auth_user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM vendors
      WHERE id = vendor_id
        AND auth_user_id = auth.uid()
    )
  );
