-- ─────────────────────────────────────────────────────────────────────────────
-- RBAC Foundation Schema
--
-- These five tables were originally created via Supabase Studio and have no
-- prior migration.  This migration version-controls the schema so it can be
-- reproduced in any environment.
--
-- All statements use CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS /
-- DO...IF NOT EXISTS patterns so they are safe to re-run against an existing
-- database that already has the tables.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. admin_users ────────────────────────────────────────────────────────────
-- One row per admin panel user.  auth_user_id links to auth.users.id.
-- is_active = false disables login without deleting the record (audit trail).
-- is_super_admin = true bypasses all permission checks at the application layer.

CREATE TABLE IF NOT EXISTS public.admin_users (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id    UUID        NOT NULL,
  full_name       TEXT        NOT NULL DEFAULT '',
  email           TEXT        NOT NULL DEFAULT '',
  is_super_admin  BOOLEAN     NOT NULL DEFAULT FALSE,
  is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
  last_login_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS admin_users_auth_user_id_key
  ON public.admin_users (auth_user_id);

-- ── 2. roles ──────────────────────────────────────────────────────────────────
-- Named groups of permissions.
-- is_system = true marks built-in roles that should not be deleted via the UI.

CREATE TABLE IF NOT EXISTS public.roles (
  id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT    NOT NULL,
  description TEXT,
  is_system   BOOLEAN NOT NULL DEFAULT FALSE,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE UNIQUE INDEX IF NOT EXISTS roles_name_key ON public.roles (name);

-- ── 3. permissions ────────────────────────────────────────────────────────────
-- Atomic capabilities identified by dot-namespaced keys (e.g. booking.view).
-- description is optional; module is derived client-side from the name prefix.

CREATE TABLE IF NOT EXISTS public.permissions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  description TEXT
);

-- Note: a UNIQUE constraint on permissions.name is added in a later migration
-- (20260927000006) after existing duplicates are cleaned up.

-- ── 4. role_permissions ───────────────────────────────────────────────────────
-- Many-to-many join: which permissions belong to each role.
-- Column is named permissions_id (not permission_id) — matches existing data.

CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id        UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permissions_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permissions_id)
);

CREATE INDEX IF NOT EXISTS role_permissions_permissions_id_idx
  ON public.role_permissions (permissions_id);

-- ── 5. admin_user_roles ───────────────────────────────────────────────────────
-- Many-to-many join: which roles are assigned to each admin user.

CREATE TABLE IF NOT EXISTS public.admin_user_roles (
  admin_user_id UUID NOT NULL REFERENCES public.admin_users(id) ON DELETE CASCADE,
  role_id       UUID NOT NULL REFERENCES public.roles(id)       ON DELETE CASCADE,
  PRIMARY KEY (admin_user_id, role_id)
);

CREATE INDEX IF NOT EXISTS admin_user_roles_role_id_idx
  ON public.admin_user_roles (role_id);

-- ── 6. Row-Level Security ─────────────────────────────────────────────────────
-- Enable RLS on all five tables.  ALTER TABLE ... ENABLE ROW LEVEL SECURITY is
-- idempotent — safe to run if it is already enabled.

ALTER TABLE public.admin_users       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_user_roles  ENABLE ROW LEVEL SECURITY;

-- ── 7. admin_users SELECT policy ─────────────────────────────────────────────
-- "admin_users: authenticated user can read own row"
-- This policy was previously created by migration 20260609000001.  We guard
-- with IF NOT EXISTS to avoid an error when this migration is applied to a
-- database that already has it.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'admin_users'
      AND policyname = 'admin_users: authenticated user can read own row'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "admin_users: authenticated user can read own row"
        ON public.admin_users
        FOR SELECT
        TO authenticated
        USING (auth.uid() = auth_user_id)
    $policy$;
  END IF;
END;
$$;
