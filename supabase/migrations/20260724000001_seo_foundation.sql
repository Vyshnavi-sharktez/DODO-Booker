-- ── SEO Foundation — Phase 1 ──────────────────────────────────────────────────
--
-- Creates two tables:
--
--   catalog_node_seo    — per-node SEO configuration, separate from catalog data.
--                         FK to catalog_nodes (CASCADE DELETE).  One optional row
--                         per node; rows only exist for nodes that have been
--                         configured.
--
--   seo_global_settings — singleton row (id = 'global') for brand-wide SEO
--                         defaults and templates.  No production values seeded;
--                         admin fills this in after deployment.
--
-- Ownership model (which system owns what):
--   seo_global_settings → Brand name, domain, OG defaults, title template,
--                         homepage SEO.
--   catalog_node_seo    → Per-catalog-node title, description, OG overrides,
--                         editorial body content, noindex flag.
--   seo_settings        → UNCHANGED; continues serving per-slug CMS page SEO.
--
-- RLS pattern matches existing admin tables (seo_settings, catalog_node_configs):
--   Any authenticated Supabase session (= logged-in admin) can read/write.
--   Permission enforcement (settings.manage) is at the Flutter RBAC layer.
--   No anon read: SEO config is not consumed by the customer app in Phase 1.
--
-- Safe to re-run: uses IF NOT EXISTS / DROP IF EXISTS / CREATE OR REPLACE.
-- Does NOT touch catalog_nodes, catalog_node_relationships, seo_settings,
-- or any booking/business table.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── catalog_node_seo ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS catalog_node_seo (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  node_id              UUID        NOT NULL UNIQUE
                                   REFERENCES catalog_nodes(id) ON DELETE CASCADE,

  -- Page-level metadata
  seo_title            TEXT,       -- ~50-60 chars recommended; shown in SERP title
  seo_description      TEXT,       -- ~120-160 chars recommended; shown in SERP snippet

  -- Open Graph / social overrides (null = fall back to seo_title/seo_description)
  og_title             TEXT,
  og_description       TEXT,
  og_image_url         TEXT,

  -- Editorial content for the future SEO page body
  seo_content          TEXT,

  -- Editorial guidance only: NOT stored as keywords, NOT auto-injected anywhere.
  -- Records the target search intent for this catalog node.
  primary_search_topic TEXT,

  -- When true: the future generation script will add <meta name="robots"
  -- content="noindex"> and exclude this node from sitemap.xml.
  noindex              BOOLEAN     NOT NULL DEFAULT false,

  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_catalog_node_seo_node_id
  ON catalog_node_seo (node_id);

-- ── seo_global_settings ───────────────────────────────────────────────────────
-- Singleton enforced by CHECK (id = 'global').
-- No default values seeded — admin provides real content after deployment.

CREATE TABLE IF NOT EXISTS seo_global_settings (
  id                       TEXT        PRIMARY KEY DEFAULT 'global'
                                        CHECK (id = 'global'),

  brand_name               TEXT,       -- e.g. "DODO Booker"
  brand_tagline            TEXT,       -- short brand tagline

  -- Production domain: null until hosting is finalised.
  -- If set, must be a valid https:// URL (validated in admin UI).
  production_domain        TEXT,

  default_og_image_url     TEXT,       -- fallback OG image for all pages

  -- Title template for generated pages, e.g. "{page_title} | DODO Booker"
  -- {page_title} is a placeholder replaced at generation time.
  title_template           TEXT,

  homepage_seo_title       TEXT,       -- SEO title for the homepage
  homepage_seo_description TEXT,       -- meta description for the homepage

  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── updated_at triggers ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_seo_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_catalog_node_seo_updated_at   ON catalog_node_seo;
DROP TRIGGER IF EXISTS trg_seo_global_settings_updated_at ON seo_global_settings;

CREATE TRIGGER trg_catalog_node_seo_updated_at
  BEFORE UPDATE ON catalog_node_seo
  FOR EACH ROW EXECUTE FUNCTION fn_seo_updated_at();

CREATE TRIGGER trg_seo_global_settings_updated_at
  BEFORE UPDATE ON seo_global_settings
  FOR EACH ROW EXECUTE FUNCTION fn_seo_updated_at();

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE catalog_node_seo    ENABLE ROW LEVEL SECURITY;
ALTER TABLE seo_global_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cns_authenticated_all" ON catalog_node_seo;
DROP POLICY IF EXISTS "sgs_authenticated_all" ON seo_global_settings;

CREATE POLICY "cns_authenticated_all"
  ON catalog_node_seo FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY "sgs_authenticated_all"
  ON seo_global_settings FOR ALL TO authenticated
  USING (true) WITH CHECK (true);
