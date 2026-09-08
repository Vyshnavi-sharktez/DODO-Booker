-- Vendors can delete their own pending requests only
CREATE POLICY "vsr_vendor_delete_pending" ON vendor_service_requests
  FOR DELETE TO authenticated
  USING (
    vendor_id = auth.uid()
    AND status = 'pending'
  );
