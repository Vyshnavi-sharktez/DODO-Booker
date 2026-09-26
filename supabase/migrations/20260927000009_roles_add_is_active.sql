-- ─────────────────────────────────────────────────────────────────────────────
-- Add is_active column to roles
--
-- The roles table was created via Supabase Studio before migration
-- 20260927000001 ran.  CREATE TABLE IF NOT EXISTS was a no-op, so
-- is_active (and is_system, fixed in 20260927000008) were never added.
--
-- Default TRUE keeps all existing roles active after the column is added.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.roles
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
