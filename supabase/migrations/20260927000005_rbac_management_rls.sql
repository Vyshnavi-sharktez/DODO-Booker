-- ─────────────────────────────────────────────────────────────────────────────
-- RBAC Management Write Policies
--
-- The admin panel uses the anon/authenticated key (not service_role), so all
-- writes to RBAC tables go through RLS.  The only existing policy was a SELECT
-- on admin_users (created by 20260609000001 / codified in 20260927000001).
--
-- This migration adds write policies so the RBAC management UI can:
--   • Create, update, and deactivate roles
--   • Assign/remove permissions from roles
--   • Update admin user records (full_name, is_active)
--   • Assign/remove roles from admin users
--   • Read all roles, permissions, and admin_user_roles (cross-user queries)
--
-- Authorization rule: any active admin (is_active = TRUE) may perform RBAC
-- management operations.  The application layer additionally enforces the
-- rbac.manage permission check before the RBAC page is accessible.
--
-- admin_users INSERT is intentionally excluded — new admins are provisioned
-- through Supabase Auth Studio (invite flow), not via the application layer.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Helper: active-admin predicate (reused in every policy) ──────────────────

-- Not a function — just the inline subquery used in each policy USING clause:
--   EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active = TRUE)

-- ── roles ─────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='roles' AND policyname='Active admin: full access to roles'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Active admin: full access to roles"
        ON public.roles FOR ALL TO authenticated
        USING (
          EXISTS (
            SELECT 1 FROM public.admin_users
            WHERE auth_user_id = auth.uid() AND is_active = TRUE
          )
        )
        WITH CHECK (
          EXISTS (
            SELECT 1 FROM public.admin_users
            WHERE auth_user_id = auth.uid() AND is_active = TRUE
          )
        )
    $p$;
  END IF;
END;
$$;

-- ── permissions ───────────────────────────────────────────────────────────────
-- Permissions are read-only from the application layer (created only via
-- migrations).  Any active admin may read them.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='permissions' AND policyname='Active admin: read permissions'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Active admin: read permissions"
        ON public.permissions FOR SELECT TO authenticated
        USING (
          EXISTS (
            SELECT 1 FROM public.admin_users
            WHERE auth_user_id = auth.uid() AND is_active = TRUE
          )
        )
    $p$;
  END IF;
END;
$$;

-- ── role_permissions ──────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='role_permissions' AND policyname='Active admin: full access to role_permissions'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Active admin: full access to role_permissions"
        ON public.role_permissions FOR ALL TO authenticated
        USING (
          EXISTS (
            SELECT 1 FROM public.admin_users
            WHERE auth_user_id = auth.uid() AND is_active = TRUE
          )
        )
        WITH CHECK (
          EXISTS (
            SELECT 1 FROM public.admin_users
            WHERE auth_user_id = auth.uid() AND is_active = TRUE
          )
        )
    $p$;
  END IF;
END;
$$;

-- ── admin_users: UPDATE and read-all ─────────────────────────────────────────
-- The existing SELECT policy allows an admin to read their own row only.
-- The RBAC management UI needs to read ALL admin rows and update any row
-- (e.g., deactivating another admin).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='admin_users' AND policyname='Active admin: read all admin users'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Active admin: read all admin users"
        ON public.admin_users FOR SELECT TO authenticated
        USING (
          EXISTS (
            SELECT 1 FROM public.admin_users self
            WHERE self.auth_user_id = auth.uid() AND self.is_active = TRUE
          )
        )
    $p$;
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='admin_users' AND policyname='Active admin: update admin users'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Active admin: update admin users"
        ON public.admin_users FOR UPDATE TO authenticated
        USING (
          EXISTS (
            SELECT 1 FROM public.admin_users self
            WHERE self.auth_user_id = auth.uid() AND self.is_active = TRUE
          )
        )
        WITH CHECK (
          EXISTS (
            SELECT 1 FROM public.admin_users self
            WHERE self.auth_user_id = auth.uid() AND self.is_active = TRUE
          )
        )
    $p$;
  END IF;
END;
$$;

-- ── admin_user_roles ─────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='admin_user_roles' AND policyname='Active admin: full access to admin_user_roles'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Active admin: full access to admin_user_roles"
        ON public.admin_user_roles FOR ALL TO authenticated
        USING (
          EXISTS (
            SELECT 1 FROM public.admin_users
            WHERE auth_user_id = auth.uid() AND is_active = TRUE
          )
        )
        WITH CHECK (
          EXISTS (
            SELECT 1 FROM public.admin_users
            WHERE auth_user_id = auth.uid() AND is_active = TRUE
          )
        )
    $p$;
  END IF;
END;
$$;
