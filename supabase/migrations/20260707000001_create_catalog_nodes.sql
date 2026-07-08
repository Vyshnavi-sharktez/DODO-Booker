-- ============================================================
-- Phase 1: Catalog Engine — Dynamic Catalog Nodes
-- ============================================================
-- Replaces the fixed 3-level (Category → SubCategory → Service)
-- hierarchy with a self-referential catalog_nodes table that
-- supports unlimited nesting.
--
-- WHAT THIS MIGRATION DOES
--   1. Creates catalog_nodes table
--   2. Migrates categories     → root nodes  (parent_id = NULL)
--   3. Migrates sub_categories → child nodes
--   4. Migrates services       → leaf nodes  (UUIDs preserved)
--   5. Adds node_id FK to service_attributes and wishlists
--   6. Backfills node_id (= service_id, since UUIDs are reused)
--   7. Creates catalog_nodes_view + catalog_node_ancestors() RPC
--   8. Enables RLS matching the project's existing patterns
--
-- WHAT THIS MIGRATION DOES NOT DO
--   - Does NOT drop categories, sub_categories, or services
--   - Does NOT change any existing FK constraints
--   - Does NOT touch booking tables
--   - Does NOT reference service_add_ons or service_faqs
--
-- SOURCE TABLE COLUMNS ACTUALLY USED
--   categories:     id, name, slug, description, image_url, icon_key,
--                   sort_order, is_active, created_at, updated_at
--   sub_categories: id, category_id, name, slug, sort_order,
--                   is_active, created_at, updated_at
--   services:       id, sub_category_id, name, slug, description,
--                   image_url, base_price, estimated_duration,
--                   is_active, created_at, updated_at
--
-- SAFE TO RE-RUN: fully idempotent.
-- ============================================================


-- ============================================================
-- 1. TABLE DEFINITION
-- ============================================================

CREATE TABLE IF NOT EXISTS catalog_nodes (
  id                 UUID           NOT NULL DEFAULT gen_random_uuid(),
  parent_id          UUID           REFERENCES catalog_nodes(id) ON DELETE RESTRICT,

  -- Traceability back to the old fixed-hierarchy tables
  legacy_id          UUID,
  legacy_type        TEXT           CHECK (legacy_type IN ('category', 'sub_category', 'service')),

  -- Display
  name               TEXT           NOT NULL,
  slug               TEXT           NOT NULL,
  description        TEXT,
  image_url          TEXT,
  icon_key           TEXT,
  sort_order         INTEGER        NOT NULL DEFAULT 0,

  -- Admin-controlled flags
  -- is_bookable is set EXPLICITLY by the admin. The system never
  -- derives it automatically from child presence.
  is_active          BOOLEAN        NOT NULL DEFAULT true,
  is_bookable        BOOLEAN        NOT NULL DEFAULT false,

  -- Service metadata — only meaningful when is_bookable = true
  base_price         NUMERIC(10,2),
  estimated_duration INTEGER,                    -- minutes

  created_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),

  CONSTRAINT catalog_nodes_pkey        PRIMARY KEY (id),
  CONSTRAINT catalog_nodes_slug_unique UNIQUE (slug)
);


-- ============================================================
-- 2. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_catalog_nodes_parent_id
  ON catalog_nodes (parent_id);

CREATE INDEX IF NOT EXISTS idx_catalog_nodes_legacy
  ON catalog_nodes (legacy_id, legacy_type);

CREATE INDEX IF NOT EXISTS idx_catalog_nodes_active
  ON catalog_nodes (is_active)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_catalog_nodes_bookable
  ON catalog_nodes (is_bookable)
  WHERE is_bookable = true;

CREATE INDEX IF NOT EXISTS idx_catalog_nodes_sort
  ON catalog_nodes (parent_id, sort_order, name);


-- ============================================================
-- 3. UPDATED_AT TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION fn_catalog_nodes_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_catalog_nodes_updated_at ON catalog_nodes;
CREATE TRIGGER trg_catalog_nodes_updated_at
  BEFORE UPDATE ON catalog_nodes
  FOR EACH ROW EXECUTE FUNCTION fn_catalog_nodes_updated_at();


-- ============================================================
-- 4. DATA MIGRATION
-- ============================================================

-- 4a. Categories → root nodes (parent_id = NULL, is_bookable = false)
--
-- Columns used from categories:
--   id, name, slug, description, image_url, icon_key,
--   sort_order, is_active, created_at, updated_at
--
-- On re-run: existing rows are updated in-place via ON CONFLICT (slug).
INSERT INTO catalog_nodes (
  id, legacy_id, legacy_type,
  parent_id,
  name, slug, description, image_url, icon_key,
  sort_order, is_active, is_bookable,
  created_at, updated_at
)
SELECT
  gen_random_uuid(),
  c.id,
  'category',
  NULL,
  c.name,
  c.slug,
  c.description,
  c.image_url,
  c.icon_key,
  COALESCE(c.sort_order, 0),
  c.is_active,
  false,
  c.created_at,
  c.updated_at
FROM categories c
ON CONFLICT (slug) DO UPDATE
  SET legacy_id   = EXCLUDED.legacy_id,
      legacy_type = EXCLUDED.legacy_type,
      name        = EXCLUDED.name,
      description = EXCLUDED.description,
      image_url   = EXCLUDED.image_url,
      icon_key    = EXCLUDED.icon_key,
      sort_order  = EXCLUDED.sort_order,
      is_active   = EXCLUDED.is_active,
      updated_at  = EXCLUDED.updated_at;


-- 4b. Sub-categories → child nodes of their category node
--
-- Columns used from sub_categories:
--   id, category_id, name, slug, sort_order, is_active,
--   created_at, updated_at
-- (sub_categories has no image_url, description, or icon_key)
INSERT INTO catalog_nodes (
  id, legacy_id, legacy_type,
  parent_id,
  name, slug, description, image_url, icon_key,
  sort_order, is_active, is_bookable,
  created_at, updated_at
)
SELECT
  gen_random_uuid(),
  sc.id,
  'sub_category',
  cat_node.id,
  sc.name,
  sc.slug,
  NULL,
  NULL,
  NULL,
  COALESCE(sc.sort_order, 0),
  sc.is_active,
  false,
  sc.created_at,
  sc.updated_at
FROM sub_categories sc
JOIN catalog_nodes cat_node
  ON  cat_node.legacy_id   = sc.category_id
  AND cat_node.legacy_type = 'category'
ON CONFLICT (slug) DO UPDATE
  SET legacy_id   = EXCLUDED.legacy_id,
      legacy_type = EXCLUDED.legacy_type,
      parent_id   = EXCLUDED.parent_id,
      name        = EXCLUDED.name,
      sort_order  = EXCLUDED.sort_order,
      is_active   = EXCLUDED.is_active,
      updated_at  = EXCLUDED.updated_at;


-- 4c. Services → leaf nodes (service UUID preserved as catalog_node id)
--
-- Columns used from services:
--   id, sub_category_id, name, slug, description, image_url,
--   base_price, estimated_duration, is_active, created_at, updated_at
--
-- is_bookable = true because all migrated services are bookable.
-- Service UUIDs are reused as catalog_node IDs so that existing
-- references (bookings, wishlists, etc.) remain valid without any
-- FK migration.
INSERT INTO catalog_nodes (
  id, legacy_id, legacy_type,
  parent_id,
  name, slug, description, image_url, icon_key,
  sort_order, is_active, is_bookable,
  base_price, estimated_duration,
  created_at, updated_at
)
SELECT
  s.id,
  s.id,
  'service',
  sc_node.id,
  s.name,
  s.slug,
  s.description,
  s.image_url,
  NULL,
  0,
  s.is_active,
  true,
  s.base_price,
  s.estimated_duration,
  s.created_at,
  s.updated_at
FROM services s
JOIN catalog_nodes sc_node
  ON  sc_node.legacy_id   = s.sub_category_id
  AND sc_node.legacy_type = 'sub_category'
ON CONFLICT (id) DO UPDATE
  SET legacy_id          = EXCLUDED.legacy_id,
      legacy_type        = EXCLUDED.legacy_type,
      parent_id          = EXCLUDED.parent_id,
      name               = EXCLUDED.name,
      slug               = EXCLUDED.slug,
      description        = EXCLUDED.description,
      image_url          = EXCLUDED.image_url,
      sort_order         = EXCLUDED.sort_order,
      is_active          = EXCLUDED.is_active,
      is_bookable        = EXCLUDED.is_bookable,
      base_price         = EXCLUDED.base_price,
      estimated_duration = EXCLUDED.estimated_duration,
      updated_at         = EXCLUDED.updated_at;


-- ============================================================
-- 5. ADD node_id TO RELATED TABLES
-- ============================================================
-- Only tables confirmed to exist are referenced here.
-- node_id is nullable so existing NOT NULL constraints on
-- service_id are undisturbed.

ALTER TABLE service_attributes
  ADD COLUMN IF NOT EXISTS node_id UUID REFERENCES catalog_nodes(id);

ALTER TABLE wishlists
  ADD COLUMN IF NOT EXISTS node_id UUID REFERENCES catalog_nodes(id);

CREATE INDEX IF NOT EXISTS idx_service_attributes_node_id
  ON service_attributes (node_id);

CREATE INDEX IF NOT EXISTS idx_wishlists_node_id
  ON wishlists (node_id);


-- ============================================================
-- 6. BACKFILL node_id
-- ============================================================
-- Service UUIDs are reused as catalog_node IDs, so node_id = service_id.

UPDATE service_attributes
  SET node_id = service_id
  WHERE node_id IS NULL
    AND service_id IS NOT NULL;

UPDATE wishlists
  SET node_id = service_id
  WHERE node_id IS NULL
    AND service_id IS NOT NULL;


-- ============================================================
-- 7. HELPER VIEW
-- ============================================================
-- children_count lets Flutter decide whether to show a grid of
-- children or a Book Now button without a second round-trip.

CREATE OR REPLACE VIEW catalog_nodes_view AS
SELECT
  n.*,
  (
    SELECT COUNT(*)::INTEGER
    FROM   catalog_nodes c
    WHERE  c.parent_id = n.id
      AND  c.is_active = true
  )                    AS children_count,
  p.name               AS parent_name,
  p.slug               AS parent_slug
FROM  catalog_nodes n
LEFT JOIN catalog_nodes p ON p.id = n.parent_id;


-- ============================================================
-- 8. BREADCRUMB FUNCTION
-- ============================================================
-- Returns the ancestor chain from root down to the given node.
-- Depth 0 = the node itself; highest depth = root.

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
    SELECT n.id, n.parent_id, n.name, n.slug, 0 AS depth
    FROM   catalog_nodes n
    WHERE  n.id = p_node_id

    UNION ALL

    SELECT n.id, n.parent_id, n.name, n.slug, a.depth + 1
    FROM   catalog_nodes n
    JOIN   ancestors a ON n.id = a.parent_id
  )
  SELECT id, name, slug, depth
  FROM   ancestors
  ORDER  BY depth DESC;
$$;


-- ============================================================
-- 9. ROW LEVEL SECURITY
-- ============================================================
-- Pattern matches existing catalog tables in this project:
--   • anon + authenticated can SELECT active nodes
--   • authenticated can perform all writes (admin panel uses
--     Supabase email/password → authenticated role)
-- DO-blocks guard against errors on re-run.

ALTER TABLE catalog_nodes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE  schemaname = 'public'
      AND  tablename  = 'catalog_nodes'
      AND  policyname = 'catalog_nodes: public read active'
  ) THEN
    CREATE POLICY "catalog_nodes: public read active"
      ON catalog_nodes
      FOR SELECT
      TO anon, authenticated
      USING (is_active = true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE  schemaname = 'public'
      AND  tablename  = 'catalog_nodes'
      AND  policyname = 'catalog_nodes: authenticated full access'
  ) THEN
    CREATE POLICY "catalog_nodes: authenticated full access"
      ON catalog_nodes
      FOR ALL
      TO authenticated
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;


-- ============================================================
-- 10. VERIFICATION QUERIES  (run manually to confirm success)
-- ============================================================
--
-- Row counts should match source tables:
--   SELECT legacy_type, COUNT(*) FROM catalog_nodes GROUP BY legacy_type;
--
-- Every service must have a matching node:
--   SELECT COUNT(*) FROM services s
--   LEFT JOIN catalog_nodes cn ON cn.id = s.id
--   WHERE cn.id IS NULL;
--   -- expect 0
--
-- No orphaned sub-category nodes:
--   SELECT COUNT(*) FROM catalog_nodes
--   WHERE legacy_type = 'sub_category' AND parent_id IS NULL;
--   -- expect 0
--
-- No orphaned service nodes:
--   SELECT COUNT(*) FROM catalog_nodes
--   WHERE legacy_type = 'service' AND parent_id IS NULL;
--   -- expect 0
--
-- node_id backfill complete:
--   SELECT COUNT(*) FROM service_attributes
--   WHERE node_id IS NULL AND service_id IS NOT NULL;
--   -- expect 0
--
--   SELECT COUNT(*) FROM wishlists
--   WHERE node_id IS NULL AND service_id IS NOT NULL;
--   -- expect 0
