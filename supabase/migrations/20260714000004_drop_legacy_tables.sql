-- ============================================================
-- Migration: drop legacy categories / sub_categories / services
-- ============================================================
-- PRECONDITIONS (enforced by migration ordering):
--   1. All Dart code references have been replaced (migration series
--      20260714000001–000003 code changes + app deployment).
--   2. All FK constraints on dependent tables have been retargeted
--      to catalog_nodes (migration 20260714000003).
--   3. rating + review_count backfilled from services (migration 000002).
--
-- DROP ORDER: services first (references sub_categories + categories),
-- then sub_categories (references categories), then categories.
-- CASCADE handles any remaining internal constraints.
-- ============================================================

-- Drop services (references sub_categories and categories)
DROP TABLE IF EXISTS services CASCADE;

-- Drop sub_categories (references categories)
DROP TABLE IF EXISTS sub_categories CASCADE;

-- Drop categories (leaf of legacy hierarchy)
DROP TABLE IF EXISTS categories CASCADE;
