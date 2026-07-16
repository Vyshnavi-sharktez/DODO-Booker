-- Allow vendor app (anon Supabase client) to manage serving-area assignments.
--
-- The vendor app does not use Supabase Auth; it authenticates against
-- vendor_dev_auth and stores session in SharedPreferences.  All Supabase
-- calls from the vendor app therefore run as the anon role.
--
-- The existing vsaa_anon_read policy only grants SELECT; DELETE and INSERT
-- from syncAssignments() are rejected without this policy.
--
-- Application-level scoping: the vendor app always passes its own
-- vendors.id as vendor_id, matching the pattern established by the
-- anon_update_vendors policy on the vendors table.

CREATE POLICY "vsaa_anon_write"
  ON vendor_serving_area_assignments
  FOR ALL TO anon
  USING (true)
  WITH CHECK (true);
