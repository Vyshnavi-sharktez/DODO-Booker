-- ─────────────────────────────────────────────────────────────────────────────
-- Protect system roles from modification or deletion
--
-- 1. Ensure the Super Admin role has is_system = TRUE (it was created manually
--    in Studio without setting this flag).
-- 2. Trigger on roles: block UPDATE or DELETE when is_system = TRUE.
-- 3. Trigger on role_permissions: block INSERT or DELETE when the role is a
--    system role (covers the delete-then-insert pattern in setRolePermissions).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Ensure is_system column exists, then mark Super Admin ─────────────────
-- The roles table was created via Studio and may be missing this column.

ALTER TABLE public.roles
  ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.roles
SET is_system = TRUE
WHERE lower(trim(name)) IN ('super admin', 'superadmin', 'super_admin')
  AND is_system = FALSE;

-- ── 2. Guard function for roles ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.guard_system_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF (TG_OP = 'DELETE' AND OLD.is_system) OR
     (TG_OP = 'UPDATE' AND OLD.is_system) THEN
    RAISE EXCEPTION 'System roles cannot be modified or deleted.'
      USING ERRCODE = 'P0001';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS roles_guard_system ON public.roles;
CREATE TRIGGER roles_guard_system
  BEFORE UPDATE OR DELETE ON public.roles
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_system_role();

-- ── 3. Guard function for role_permissions ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.guard_system_role_permissions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role_id UUID;
BEGIN
  v_role_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.role_id ELSE NEW.role_id END;
  IF EXISTS (
    SELECT 1 FROM public.roles
    WHERE id = v_role_id AND is_system = TRUE
  ) THEN
    RAISE EXCEPTION 'Permissions of system roles cannot be modified.'
      USING ERRCODE = 'P0001';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS role_permissions_guard_system ON public.role_permissions;
CREATE TRIGGER role_permissions_guard_system
  BEFORE INSERT OR DELETE ON public.role_permissions
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_system_role_permissions();
