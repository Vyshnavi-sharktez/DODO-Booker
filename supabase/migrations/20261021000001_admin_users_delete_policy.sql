-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: missing DELETE RLS policies on admin_users and vendors.
--
-- admin_users previously had SELECT + UPDATE policies (20260927000005 /
-- 20260927000007) but no DELETE policy, so every delete attempt was silently
-- rejected by PostgreSQL RLS.
--
-- vendors only had anon_update_vendors (FOR UPDATE TO anon). Authenticated
-- admins had no DELETE policy, so vendor deletions also failed.
--
-- Guards:
--   • admin_users DELETE: caller must be an active admin AND the target row
--     must not be a super-admin (super-admins are only removable via the
--     Supabase dashboard / service-role).
--   • vendors DELETE: caller must be an active admin (no extra row-level
--     restriction needed; business-data preservation is enforced at the
--     application layer).
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'admin_users'
      AND policyname = 'Active admin: delete admin users'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Active admin: delete admin users"
        ON public.admin_users
        FOR DELETE
        TO authenticated
        USING (
          public.is_active_admin()
          AND is_super_admin = FALSE
        )
    $p$;
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'vendors'
      AND policyname = 'Active admin: delete vendors'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Active admin: delete vendors"
        ON public.vendors
        FOR DELETE
        TO authenticated
        USING (public.is_active_admin())
    $p$;
  END IF;
END;
$$;
