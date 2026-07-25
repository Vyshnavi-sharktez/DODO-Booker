-- ── Phase 4: Location SEO Pages ──────────────────────────────────────────────
--
-- Two changes:
--
--   1. Add `slug` column to service_availability_areas.
--      Safe multi-step approach:
--        a) Add nullable column
--        b) Backfill from name (URL-safe: lowercase, hyphens, no leading/trailing)
--        c) Deduplicate: same-slug rows get -2, -3 suffixes (city/name/created_at order)
--        d) Verify no duplicates remain
--        e) Enforce NOT NULL + UNIQUE
--        f) Add BEFORE INSERT trigger for future rows (auto-derives from name)
--
--   2. Create `location_node_seo` table for admin-curated area × node SEO configs.
--      Security: authenticated only — no anon read.
--      Generator reads via service-role key (bypasses RLS).
--
-- Does NOT touch: catalog_nodes, catalog_node_seo, seo_global_settings,
-- catalog_node_location_restrictions, or any booking/serviceability tables.
--
-- Serviceability validation note:
--   catalog_node_location_restrictions links nodes to areas they are BLOCKED in
--   (not areas they are available in). This table is for booking enforcement only.
--   For SEO publishing, explicit admin curation via location_node_seo is the sole
--   gate — the generator adds a runtime warning for node-scoped blocks but does not
--   attempt to infer positive availability from absence of restrictions.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1a. Add nullable slug column ─────────────────────────────────────────────

ALTER TABLE service_availability_areas
  ADD COLUMN IF NOT EXISTS slug TEXT;

-- ── 1b. Backfill initial slugs from name ─────────────────────────────────────
-- Derive: lowercase, replace any run of non-alphanumeric with a single hyphen,
-- strip leading/trailing hyphens.
-- Only fills NULL rows so re-running is safe.

UPDATE service_availability_areas
SET slug = lower(
  regexp_replace(
    regexp_replace(trim(name), '[^a-zA-Z0-9]+', '-', 'g'),
    '^-+|-+$', '', 'g'
  )
)
WHERE slug IS NULL;

-- ── 1c. Deduplicate slugs ─────────────────────────────────────────────────────
-- Within each group of areas that share the same initial slug:
--   • The first row (by city ASC, name ASC, created_at ASC) keeps the base slug.
--   • Subsequent rows receive -2, -3, … suffixes.
-- This handles same-named areas in different cities deterministically.

DO $$
DECLARE
  r      RECORD;
  v_base TEXT;
  v_n    INT;
  v_slug TEXT;
BEGIN
  FOR r IN (
    WITH ranked AS (
      SELECT id,
             slug,
             ROW_NUMBER() OVER (
               PARTITION BY slug
               ORDER BY city ASC, name ASC, created_at ASC
             ) AS rn
      FROM service_availability_areas
    )
    SELECT id, slug AS base_slug, rn
    FROM   ranked
    WHERE  rn > 1
    ORDER  BY base_slug, rn
  ) LOOP
    v_base := r.base_slug;
    v_n    := r.rn;          -- start suffix hint from rank
    v_slug := v_base || '-' || v_n::TEXT;

    -- If the suffixed candidate is also taken, keep incrementing
    WHILE EXISTS (
      SELECT 1 FROM service_availability_areas
      WHERE  slug = v_slug AND id <> r.id
    ) LOOP
      v_n    := v_n + 1;
      v_slug := v_base || '-' || v_n::TEXT;
    END LOOP;

    UPDATE service_availability_areas
    SET    slug = v_slug
    WHERE  id = r.id;
  END LOOP;
END;
$$;

-- ── 1d. Verify uniqueness before enforcing the constraint ─────────────────────

DO $$
BEGIN
  IF EXISTS (
    SELECT slug
    FROM   service_availability_areas
    GROUP  BY slug
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Phase 4 migration: duplicate slugs remain after deduplication. '
      'Inspect service_availability_areas.slug and resolve manually.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM service_availability_areas WHERE slug IS NULL OR slug = ''
  ) THEN
    RAISE EXCEPTION
      'Phase 4 migration: one or more areas have a NULL or empty slug after backfill.';
  END IF;
END;
$$;

-- ── 1e. Enforce NOT NULL + UNIQUE ─────────────────────────────────────────────

ALTER TABLE service_availability_areas
  ALTER COLUMN slug SET NOT NULL;

ALTER TABLE service_availability_areas
  ADD CONSTRAINT uq_saa_slug UNIQUE (slug);

-- ── 1f. Auto-slug trigger for future INSERTs ─────────────────────────────────
-- When a new area is inserted with slug = NULL or '', derives the slug from
-- name and ensures uniqueness. An explicit non-empty slug is kept as-is.

CREATE OR REPLACE FUNCTION fn_saa_auto_slug()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_base   TEXT;
  v_slug   TEXT;
  v_suffix INT := 0;
BEGIN
  IF NEW.slug IS NOT NULL AND NEW.slug <> '' THEN
    RETURN NEW;
  END IF;

  v_base := lower(
    regexp_replace(
      regexp_replace(trim(NEW.name), '[^a-zA-Z0-9]+', '-', 'g'),
      '^-+|-+$', '', 'g'
    )
  );
  v_slug := v_base;

  WHILE EXISTS (
    SELECT 1 FROM service_availability_areas WHERE slug = v_slug
  ) LOOP
    v_suffix := v_suffix + 1;
    v_slug   := v_base || '-' || v_suffix::TEXT;
  END LOOP;

  NEW.slug := v_slug;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_saa_auto_slug
  BEFORE INSERT ON service_availability_areas
  FOR EACH ROW
  EXECUTE FUNCTION fn_saa_auto_slug();

-- ── 2. location_node_seo table ────────────────────────────────────────────────

CREATE TABLE location_node_seo (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

  area_id         UUID        NOT NULL
                              REFERENCES service_availability_areas(id)
                              ON DELETE CASCADE,

  node_id         UUID        NOT NULL
                              REFERENCES catalog_nodes(id)
                              ON DELETE CASCADE,

  -- Page-level SEO metadata
  seo_title       TEXT,       -- ~50–70 chars; template: "{name} in {area}"
  seo_description TEXT,       -- ~120–160 chars; location-specific meta description

  -- Open Graph / social overrides (null = inherit from seo_title/description)
  og_title        TEXT,
  og_description  TEXT,
  og_image_url    TEXT,

  -- Admin-authored area-specific body text.
  -- This is the primary content differentiator from the generic service page.
  -- Required for a quality page; health badge reflects its presence.
  seo_content     TEXT,

  -- When true: generated page carries <meta name="robots" content="noindex, follow">
  -- and is excluded from sitemap.xml.
  noindex         BOOLEAN     NOT NULL DEFAULT false,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- One SEO config per area × node combination
  CONSTRAINT uq_lns_area_node UNIQUE (area_id, node_id)
);

CREATE INDEX idx_lns_area_id ON location_node_seo (area_id);
CREATE INDEX idx_lns_node_id ON location_node_seo (node_id);

-- ── RLS: authenticated only, no anon access ────────────────────────────────────
-- SEO configuration is private data. The Node.js generator reads via the
-- service-role key (bypasses RLS). The admin panel reads/writes via authenticated
-- Supabase sessions. The customer app never touches this table.

ALTER TABLE location_node_seo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "lns_authenticated_all"
  ON location_node_seo FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ── updated_at trigger ─────────────────────────────────────────────────────────
-- Reuses fn_seo_updated_at() created in 20260724000001_seo_foundation.sql.

CREATE TRIGGER trg_location_node_seo_updated_at
  BEFORE UPDATE ON location_node_seo
  FOR EACH ROW EXECUTE FUNCTION fn_seo_updated_at();
