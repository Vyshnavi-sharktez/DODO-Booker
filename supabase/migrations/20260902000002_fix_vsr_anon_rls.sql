-- Fix vendor_service_requests RLS and storage policies for the anon role.
--
-- The vendor app does not use Supabase Auth (same pattern as vendor_dev_auth /
-- SharedPreferences session described in 20260715000012).  All calls from the
-- vendor app run as the anon role, so auth.uid() is always NULL.  The original
-- policies targeted the `authenticated` role and therefore always failed.

-- ── Table: vendor_service_requests ───────────────────────────────────────────

-- Remove authenticated policies that can never be reached by the vendor app.
DROP POLICY IF EXISTS "vsr_vendor_insert" ON vendor_service_requests;
DROP POLICY IF EXISTS "vsr_select"        ON vendor_service_requests;

-- Vendors (anon): insert own requests.
-- Application-level scoping: the vendor app always supplies its own
-- vendors.id as vendor_id, matching the pattern in anon_update_vendors and
-- vsaa_anon_write.
CREATE POLICY "vsr_vendor_insert_anon" ON vendor_service_requests
  FOR INSERT TO anon
  WITH CHECK (true);

-- Vendors (anon): read own requests.  The vendor app always filters by its
-- own vendor_id in the query, so exposing all rows to anon is consistent
-- with the existing open-read pattern for vendor-owned tables.
CREATE POLICY "vsr_vendor_select_anon" ON vendor_service_requests
  FOR SELECT TO anon
  USING (true);

-- Admin: select all (authenticated, existing policy retained).
-- Re-create cleanly so it doesn't depend on auth.uid() matching a vendor.
DROP POLICY IF EXISTS "vsr_admin_select" ON vendor_service_requests;
CREATE POLICY "vsr_admin_select" ON vendor_service_requests
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()));

-- ── Storage: vendor-requests bucket ──────────────────────────────────────────

-- The upload policy also targeted `authenticated` and used auth.uid() for
-- folder scoping — both wrong for the anon vendor app.
DROP POLICY IF EXISTS "vsr_vendor_upload" ON storage.objects;

CREATE POLICY "vsr_anon_upload" ON storage.objects
  FOR INSERT TO anon
  WITH CHECK (bucket_id = 'vendor-requests');
