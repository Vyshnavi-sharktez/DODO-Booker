-- ── vendor_services: admin SELECT policy ──────────────────────────────────────
--
-- The vendor_services table was created before migration tracking began.
-- Its original RLS was written when the vendor app used anonymous Supabase calls,
-- so only anon-role policies existed. No admin SELECT policy was ever added.
--
-- The admin panel (authenticated role, admin JWT) therefore receives 0 rows when
-- querying vendor_services directly — RLS silently filters everything out.
-- vendor_service_requests has an equivalent admin policy (vsr_select); this
-- mirrors that pattern for vendor_services.
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "vendor_services_admin_select" ON vendor_services;
CREATE POLICY "vendor_services_admin_select" ON vendor_services
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );
