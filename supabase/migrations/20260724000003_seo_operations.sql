-- ── SEO Operations — Phase 5 ──────────────────────────────────────────────────
--
-- Adds last_generation_at to seo_global_settings for staleness tracking.
--
-- IMPORTANT: last_generation_at is written ONLY by the SEO generator after
-- all pages are generated AND validation passes. The updated_at trigger is
-- replaced with a version that does NOT bump updated_at when only
-- last_generation_at changes, so staleness comparisons remain correct.
--
-- Safe to re-run: uses ADD COLUMN IF NOT EXISTS / CREATE OR REPLACE.
-- Does NOT touch catalog_node_seo, location_node_seo, RLS, or any other table.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Add column ────────────────────────────────────────────────────────────────

ALTER TABLE seo_global_settings
  ADD COLUMN IF NOT EXISTS last_generation_at TIMESTAMPTZ;

-- ── Specialised updated_at trigger for seo_global_settings ───────────────────
--
-- Replaces the generic fn_seo_updated_at() trigger on this table so that when
-- the SEO generator writes last_generation_at (and nothing else changes),
-- updated_at is NOT bumped. This ensures staleness comparisons work correctly:
--   updated_at  → when the admin last changed SEO configuration
--   last_generation_at → when the generator last succeeded
--
-- catalog_node_seo continues to use the existing fn_seo_updated_at() trigger.

CREATE OR REPLACE FUNCTION fn_seo_global_settings_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- If only last_generation_at changed (generator update), preserve updated_at.
  IF NEW.last_generation_at IS DISTINCT FROM OLD.last_generation_at AND
     NEW.brand_name IS NOT DISTINCT FROM OLD.brand_name AND
     NEW.brand_tagline IS NOT DISTINCT FROM OLD.brand_tagline AND
     NEW.production_domain IS NOT DISTINCT FROM OLD.production_domain AND
     NEW.default_og_image_url IS NOT DISTINCT FROM OLD.default_og_image_url AND
     NEW.title_template IS NOT DISTINCT FROM OLD.title_template AND
     NEW.homepage_seo_title IS NOT DISTINCT FROM OLD.homepage_seo_title AND
     NEW.homepage_seo_description IS NOT DISTINCT FROM OLD.homepage_seo_description
  THEN
    RETURN NEW;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seo_global_settings_updated_at ON seo_global_settings;

CREATE TRIGGER trg_seo_global_settings_updated_at
  BEFORE UPDATE ON seo_global_settings
  FOR EACH ROW EXECUTE FUNCTION fn_seo_global_settings_updated_at();
