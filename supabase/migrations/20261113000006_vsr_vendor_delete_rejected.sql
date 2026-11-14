-- Allow vendors to delete their own rejected requests (dismiss from view)
CREATE POLICY "vsr_vendor_delete_rejected"
  ON vendor_service_requests
  FOR DELETE
  TO authenticated
  USING (
    status = 'rejected'
    AND EXISTS (
      SELECT 1 FROM vendors
      WHERE id = vendor_id
        AND auth_user_id = auth.uid()
    )
  );
