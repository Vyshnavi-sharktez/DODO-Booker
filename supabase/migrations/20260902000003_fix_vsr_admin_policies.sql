-- Fix vsr_admin_select and vsr_admin_update to use auth_user_id (the Supabase
-- auth UID column) instead of id (the surrogate PK), matching the pattern in
-- booking_payments (20260807000001) and auth_repository.dart.

DROP POLICY IF EXISTS "vsr_admin_select" ON vendor_service_requests;
CREATE POLICY "vsr_admin_select" ON vendor_service_requests
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

DROP POLICY IF EXISTS "vsr_admin_update" ON vendor_service_requests;
CREATE POLICY "vsr_admin_update" ON vendor_service_requests
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );
