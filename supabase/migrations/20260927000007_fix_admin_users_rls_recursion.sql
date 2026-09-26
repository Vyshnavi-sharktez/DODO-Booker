-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: infinite recursion in admin_users RLS policies
--
-- Root cause: "Active admin: read all admin users" (and the 5 companion
-- policies added by 20260927000005) use an inline subquery against
-- admin_users inside an admin_users SELECT policy.  PostgreSQL evaluates all
-- permissive policies simultaneously, so the subquery immediately re-enters
-- the same policy → 42P17.
--
-- Fix: a SECURITY DEFINER helper that queries admin_users with RLS bypassed
-- (runs as its owner, who has BYPASSRLS).  All six policies are updated to
-- call this function instead of the inline subquery.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. SECURITY DEFINER helper ───────────────────────────────────────────────
-- Runs as the function owner (postgres / superuser → BYPASSRLS).
-- Only returns TRUE/FALSE for the calling authenticated user.
-- SET search_path = '' prevents search_path-injection attacks.

CREATE OR REPLACE FUNCTION public.is_active_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE auth_user_id = auth.uid()
      AND is_active = TRUE
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_active_admin() TO authenticated;

-- ── 2. Fix the two recursive admin_users policies ────────────────────────────

ALTER POLICY "Active admin: read all admin users"
  ON public.admin_users
  USING (public.is_active_admin());

ALTER POLICY "Active admin: update admin users"
  ON public.admin_users
  USING (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- ── 3. Fix the four policies on other RBAC tables ────────────────────────────
-- These don't self-recurse, but their inline subquery on admin_users triggers
-- the recursive policy when evaluated.  Replacing with is_active_admin()
-- stops that chain.

ALTER POLICY "Active admin: full access to roles"
  ON public.roles
  USING (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

ALTER POLICY "Active admin: read permissions"
  ON public.permissions
  USING (public.is_active_admin());

ALTER POLICY "Active admin: full access to role_permissions"
  ON public.role_permissions
  USING (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

ALTER POLICY "Active admin: full access to admin_user_roles"
  ON public.admin_user_roles
  USING (public.is_active_admin())
  WITH CHECK (public.is_active_admin());
