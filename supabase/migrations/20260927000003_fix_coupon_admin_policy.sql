-- ─────────────────────────────────────────────────────────────────────────────
-- Fix Coupon Admin RLS Policy
--
-- The original "Admin full access" policy on coupons (created in
-- 20260611000003_create_coupons_table.sql) referenced admin_users.user_id,
-- which does not exist.  The correct column is admin_users.auth_user_id.
--
-- Because that migration has already been applied, we cannot edit it.  This
-- corrective migration drops the broken policy and recreates it with the
-- correct column name.
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Admin full access" ON public.coupons;

CREATE POLICY "Admin full access" ON public.coupons
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );
