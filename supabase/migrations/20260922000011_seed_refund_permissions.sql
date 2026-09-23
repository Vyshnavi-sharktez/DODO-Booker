-- ─────────────────────────────────────────────────────────────────────────────
-- Refund RBAC Permissions
--
-- Seeds the granular refund permissions into the `permissions` table.
-- After this migration, Super Admins see them automatically (isSuperAdmin
-- bypasses permission checks).  Other roles must be assigned these via the
-- RBAC management UI.
--
-- The permissions table was created outside migrations (via Supabase Studio)
-- and has no UNIQUE constraint on the name column.  ON CONFLICT (name) is
-- therefore not available.  Instead we use a filtered INSERT...SELECT so
-- this migration is idempotent without requiring any schema change.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO permissions (name)
SELECT v.name
FROM (VALUES
  ('refund.view'),             -- read refund tickets and transactions
  ('refund.review'),           -- mark under_review, request more info
  ('refund.approve'),          -- approve / partially approve / reject
  ('refund.process'),          -- initiate refund transactions
  ('refund.policy.manage')     -- manage refund policies and issue categories
) AS v(name)
WHERE NOT EXISTS (
  SELECT 1 FROM permissions p WHERE p.name = v.name
);
