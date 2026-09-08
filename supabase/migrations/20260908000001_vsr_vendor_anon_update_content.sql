-- Allow the vendor app (anon role) to UPDATE its own vendor_service_requests
-- rows so that content fields (included_items, excluded_items,
-- before_after_pairs, content_blocks) can be saved from VendorServiceConfigDialog.
--
-- Pattern mirrors vsr_vendor_insert_anon and vsr_vendor_select_anon:
-- the vendor app is responsible for scoping its own queries by vendor_id.
-- There is no auth.uid() available for the anon role, so USING (true) is
-- consistent with the existing anon policies on this table.

CREATE POLICY "vsr_vendor_update_anon" ON vendor_service_requests
  FOR UPDATE TO anon
  USING (true)
  WITH CHECK (true);
