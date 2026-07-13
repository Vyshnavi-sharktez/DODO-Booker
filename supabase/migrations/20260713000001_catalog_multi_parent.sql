-- ============================================================
-- Multi-Parent Catalog: catalog_node_relationships
-- ============================================================
-- Replaces the single parent_id column with a dedicated
-- relationship table so any catalog item can appear under
-- multiple parent categories simultaneously (cross-listed
-- services) without duplicating the item.
--
-- WHAT THIS MIGRATION DOES
--   1. Creates catalog_node_relationships table
--   2. Migrates all existing parent_id relationships into it
--   3. Nulls out parent_id (now deprecated; dropped in Phase 5)
--   4. Drops the old cycle trigger (fired on parent_id UPDATE)
--   5. Adds cycle-prevention trigger on the relationship table
--   6. Recreates catalog_nodes_view using the junction table
--   7. Updates catalog_node_ancestors() to follow first parent
--   8. Adds get_catalog_node_children() helper function
--   9. Enables RLS on catalog_node_relationships
--
-- DATA SAFETY
--   All existing parent-child relationships are migrated 1:1
--   before parent_id is nulled.  No tree structure is lost.
--   Service UUIDs, bookings, wishlists, and service_attributes
--   are entirely unaffected.
--
-- SAFE TO RE-RUN: fully idempotent via IF NOT EXISTS / OR REPLACE
-- ============================================================


-- ============================================================
-- 1. RELATIONSHIP TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS catalog_node_relationships (
  id         UUID         NOT NULL DEFAULT gen_random_uuid(),
  parent_id  UUID         NOT NULL REFERENCES catalog_nodes(id) ON DELETE CASCADE,
  child_id   UUID         NOT NULL REFERENCES catalog_nodes(id) ON DELETE CASCADE,
  sort_order INTEGER      NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  CONSTRAINT cnr_pkey        PRIMARY KEY (id),
  -- One node cannot appear under the same parent twice.
  CONSTRAINT cnr_unique_pair UNIQUE (parent_id, child_id),
  -- A node cannot be its own parent.
  CONSTRAINT cnr_no_self_loop CHECK (parent_id <> child_id)
);

-- Index for "children of parent" queries (the common read path).
CREATE INDEX IF NOT EXISTS idx_cnr_parent_id
  ON catalog_node_relationships (parent_id, sort_order);

-- Index for "parents of child" queries (needed for ancestor walk
-- and for building the parent_ids array in the view).
CREATE INDEX IF NOT EXISTS idx_cnr_child_id
  ON catalog_node_relationships (child_id);


-- ============================================================
-- 2. MIGRATE EXISTING parent_id DATA → RELATIONSHIPS
-- ============================================================
-- ON CONFLICT DO NOTHING makes this idempotent on re-run.

INSERT INTO catalog_node_relationships (parent_id, child_id, sort_order, created_at)
SELECT parent_id, id, sort_order, created_at
FROM   catalog_nodes
WHERE  parent_id IS NOT NULL
ON CONFLICT (parent_id, child_id) DO NOTHING;


-- ============================================================
-- 3. DEPRECATE parent_id ON catalog_nodes
-- ============================================================
-- The column is nulled out; all relationship data now lives in
-- catalog_node_relationships.  The column itself is kept for
-- safety and will be dropped in the Phase-5 legacy cleanup.

UPDATE catalog_nodes
  SET parent_id = NULL
  WHERE parent_id IS NOT NULL;


-- ============================================================
-- 4. DROP OLD CYCLE TRIGGER (was bound to UPDATE OF parent_id)
-- ============================================================

DROP TRIGGER IF EXISTS trg_catalog_nodes_no_cycle ON catalog_nodes;
DROP FUNCTION IF EXISTS fn_catalog_nodes_no_cycle();


-- ============================================================
-- 5. CYCLE-PREVENTION ON catalog_node_relationships
-- ============================================================
-- Before inserting or updating a relationship (parent → child),
-- walk ALL descendants of child.  If parent appears among them
-- the proposed link would form a loop → reject.

CREATE OR REPLACE FUNCTION fn_cnr_no_cycle()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  cycle_found BOOLEAN;
BEGIN
  SELECT EXISTS (
    WITH RECURSIVE descendants AS (
      SELECT NEW.child_id AS id

      UNION ALL

      SELECT r.child_id
      FROM   catalog_node_relationships r
      JOIN   descendants d ON r.parent_id = d.id
    )
    SELECT 1 FROM descendants WHERE id = NEW.parent_id
  ) INTO cycle_found;

  IF cycle_found THEN
    RAISE EXCEPTION
      'catalog_cycle: adding this relationship would create a loop.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cnr_no_cycle ON catalog_node_relationships;
CREATE TRIGGER trg_cnr_no_cycle
  BEFORE INSERT OR UPDATE ON catalog_node_relationships
  FOR EACH ROW EXECUTE FUNCTION fn_cnr_no_cycle();


-- ============================================================
-- 6. RECREATE catalog_nodes_view
-- ============================================================
-- IMPORTANT: the existing view has 24 columns established by two prior
-- migrations and must be preserved exactly:
--   20260708000002 placed minimum_order_amount at pos 15 (before created_at).
--   20260711000001 inserted loyalty columns at pos 16-19 (before created_at).
-- Using n.* is unsafe because ALTER TABLE ADD COLUMN appends at the table end,
-- producing a different physical order than the view's column order.
-- All 21 table columns and 3 derived columns are listed explicitly to match
-- the live view.  New columns (parent_ids, is_root_node) are appended last.
--
-- NOTE: get_catalog_node_children() depends on this view.
--       If this view is modified in a future migration,
--       that function must be recreated in the same migration.

CREATE OR REPLACE VIEW catalog_nodes_view AS
SELECT
  -- ── Table columns (pos 1-21) ─────────────────────────────────────────────
  -- Order matches 20260711000001_per_service_loyalty.sql exactly.
  -- minimum_order_amount is at pos 15 (explicit in 20260708000002).
  -- Loyalty columns (pos 16-19) added by 20260711000001.
  -- created_at/updated_at at pos 20-21.
  n.id,
  n.parent_id,
  n.legacy_id,
  n.legacy_type,
  n.name,
  n.slug,
  n.description,
  n.image_url,
  n.icon_key,
  n.sort_order,
  n.is_active,
  n.is_bookable,
  n.base_price,
  n.estimated_duration,
  n.minimum_order_amount,
  n.loyalty_earn_enabled,
  n.loyalty_earn_rule,
  n.loyalty_fixed_points,
  n.loyalty_earn_per_100,
  n.created_at,
  n.updated_at,

  -- ── Derived columns (pos 22-24) — same names/types, source now uses
  --    catalog_node_relationships instead of catalog_nodes.parent_id ─────────

  (
    SELECT COUNT(*)::INTEGER
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes c ON c.id = r.child_id
    WHERE  r.parent_id = n.id
      AND  c.is_active = true
  ) AS children_count,

  (
    SELECT p.name
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes p ON p.id = r.parent_id
    WHERE  r.child_id = n.id
    ORDER  BY r.sort_order ASC, r.created_at ASC
    LIMIT  1
  ) AS parent_name,

  (
    SELECT p.slug
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes p ON p.id = r.parent_id
    WHERE  r.child_id = n.id
    ORDER  BY r.sort_order ASC, r.created_at ASC
    LIMIT  1
  ) AS parent_slug,

  -- ── New columns appended at the end (pos 25-26) ───────────────────────────

  -- Ordered array of all parent UUIDs (first = canonical parent).
  -- Returns empty array [] when the item has no parents.
  COALESCE(
    (
      SELECT array_agg(r.parent_id::TEXT
                       ORDER BY r.sort_order ASC, r.created_at ASC)
      FROM   catalog_node_relationships r
      WHERE  r.child_id = n.id
    ),
    ARRAY[]::TEXT[]
  ) AS parent_ids,

  -- True when this item has no parent at all (top-level item).
  -- Use .eq('is_root_node', true) instead of .isFilter('parent_id', null).
  NOT EXISTS (
    SELECT 1
    FROM   catalog_node_relationships r
    WHERE  r.child_id = n.id
  ) AS is_root_node

FROM catalog_nodes n;


-- ============================================================
-- 7. UPDATE catalog_node_ancestors() — follow canonical parent
-- ============================================================
-- For items with multiple parents, the breadcrumb follows the
-- first relationship (lowest sort_order, then earliest created).

CREATE OR REPLACE FUNCTION catalog_node_ancestors(p_node_id UUID)
RETURNS TABLE (
  id    UUID,
  name  TEXT,
  slug  TEXT,
  depth INTEGER
)
LANGUAGE SQL
STABLE
AS $$
  WITH RECURSIVE ancestors AS (
    SELECT
      n.id,
      n.name,
      n.slug,
      0 AS depth,
      (
        SELECT r.parent_id
        FROM   catalog_node_relationships r
        WHERE  r.child_id = n.id
        ORDER  BY r.sort_order ASC, r.created_at ASC
        LIMIT  1
      ) AS first_parent_id
    FROM catalog_nodes n
    WHERE n.id = p_node_id

    UNION ALL

    SELECT
      n.id,
      n.name,
      n.slug,
      a.depth + 1,
      (
        SELECT r.parent_id
        FROM   catalog_node_relationships r
        WHERE  r.child_id = n.id
        ORDER  BY r.sort_order ASC, r.created_at ASC
        LIMIT  1
      ) AS first_parent_id
    FROM   catalog_nodes n
    JOIN   ancestors a ON n.id = a.first_parent_id
  )
  SELECT id, name, slug, depth
  FROM   ancestors
  ORDER  BY depth DESC;
$$;


-- ============================================================
-- 8. get_catalog_node_children() — children for a given parent
-- ============================================================
-- Returns all active children of p_parent_id in display order.
-- Used by the customer app instead of .eq('parent_id', ...).

CREATE OR REPLACE FUNCTION get_catalog_node_children(p_parent_id UUID)
RETURNS SETOF catalog_nodes_view
LANGUAGE SQL
STABLE
AS $$
  SELECT v.*
  FROM   catalog_node_relationships r
  JOIN   catalog_nodes_view v ON v.id = r.child_id
  WHERE  r.parent_id = p_parent_id
    AND  v.is_active = true
  ORDER  BY r.sort_order ASC, v.name ASC;
$$;


-- ============================================================
-- 9. RLS ON catalog_node_relationships
-- ============================================================

ALTER TABLE catalog_node_relationships ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'catalog_node_relationships'
      AND policyname = 'cnr: public read'
  ) THEN
    CREATE POLICY "cnr: public read"
      ON catalog_node_relationships
      FOR SELECT
      TO anon, authenticated
      USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'catalog_node_relationships'
      AND policyname = 'cnr: authenticated full access'
  ) THEN
    CREATE POLICY "cnr: authenticated full access"
      ON catalog_node_relationships
      FOR ALL
      TO authenticated
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;


-- ============================================================
-- VERIFICATION (run manually after applying)
-- ============================================================
--
-- Relationship count should equal non-root node count:
--   SELECT COUNT(*) FROM catalog_node_relationships;
--   SELECT COUNT(*) FROM catalog_nodes WHERE parent_id IS NOT NULL;
--   -- These ran BEFORE the null-out so compare against original count.
--
-- All parent_id values should now be NULL:
--   SELECT COUNT(*) FROM catalog_nodes WHERE parent_id IS NOT NULL;
--   -- expect 0
--
-- Root nodes (no parent) should match original category count:
--   SELECT COUNT(*) FROM catalog_nodes_view WHERE is_root_node = true;
--
-- Children count for any known category should be unchanged:
--   SELECT name, children_count FROM catalog_nodes_view
--   WHERE is_root_node = true ORDER BY name;
