-- Migration: CMS pages and SEO settings tables
-- Run in Supabase Dashboard → SQL Editor

-- ── CMS Pages ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS cms_pages (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  page_slug    TEXT        NOT NULL UNIQUE,
  page_title   TEXT        NOT NULL,
  page_content TEXT,
  is_published BOOLEAN     DEFAULT false NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at   TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_cms_pages_slug        ON cms_pages (page_slug);
CREATE INDEX IF NOT EXISTS idx_cms_pages_is_published ON cms_pages (is_published);

-- ── SEO Settings ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS seo_settings (
  id               UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  page_slug        TEXT        NOT NULL UNIQUE,
  meta_title       TEXT,
  meta_description TEXT,
  meta_keywords    TEXT,
  og_image_url     TEXT,
  canonical_url    TEXT,
  created_at       TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at       TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_seo_settings_slug ON seo_settings (page_slug);

-- ── Auto-update updated_at ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_cms_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cms_pages_updated_at   ON cms_pages;
DROP TRIGGER IF EXISTS trg_seo_settings_updated_at ON seo_settings;

CREATE TRIGGER trg_cms_pages_updated_at
  BEFORE UPDATE ON cms_pages
  FOR EACH ROW EXECUTE FUNCTION fn_cms_updated_at();

CREATE TRIGGER trg_seo_settings_updated_at
  BEFORE UPDATE ON seo_settings
  FOR EACH ROW EXECUTE FUNCTION fn_cms_updated_at();

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE cms_pages    ENABLE ROW LEVEL SECURITY;
ALTER TABLE seo_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cms_pages: authenticated full access"    ON cms_pages;
DROP POLICY IF EXISTS "seo_settings: authenticated full access" ON seo_settings;

CREATE POLICY "cms_pages: authenticated full access"
  ON cms_pages FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY "seo_settings: authenticated full access"
  ON seo_settings FOR ALL TO authenticated
  USING (true) WITH CHECK (true);
