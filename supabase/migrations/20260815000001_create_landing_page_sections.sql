-- Landing Page CMS: section ordering, visibility, and content management.
--
-- Architecture:
--   Admin edits draft state (any is_enabled value, any is_published value).
--   Customer reads only: is_published = true AND is_enabled = true, ordered by display_order.
--   "Publish All" in the admin sets is_published = true for enabled, false for disabled.
--
-- Access control:
--   DB layer  — RLS below (consistent with cms_pages, seo_settings pattern).
--   App layer — /dashboard/landing-page route guarded by settings.manage RBAC permission.

CREATE TABLE landing_page_sections (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  section_type  TEXT        NOT NULL,
  section_name  TEXT        NOT NULL,
  display_order INTEGER     NOT NULL DEFAULT 0,
  is_enabled    BOOLEAN     NOT NULL DEFAULT TRUE,
  is_published  BOOLEAN     NOT NULL DEFAULT FALSE,
  config        JSONB       NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION _lps_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_lps_updated_at
  BEFORE UPDATE ON landing_page_sections
  FOR EACH ROW EXECUTE FUNCTION _lps_set_updated_at();

-- ── RLS ────────────────────────────────────────────────────────────────────────

ALTER TABLE landing_page_sections ENABLE ROW LEVEL SECURITY;

-- Public (anon): read published + enabled sections only.
CREATE POLICY "lps_anon_read_published"
  ON landing_page_sections FOR SELECT TO anon
  USING (is_published = TRUE AND is_enabled = TRUE);

-- Authenticated: read all rows (admin needs draft + disabled rows).
CREATE POLICY "lps_authenticated_read_all"
  ON landing_page_sections FOR SELECT TO authenticated
  USING (TRUE);

-- Authenticated write: INSERT / UPDATE / DELETE.
-- Matches the pattern used by cms_pages and seo_settings.
-- Real access is restricted to settings.manage users via application-level RBAC.
CREATE POLICY "lps_authenticated_write"
  ON landing_page_sections FOR ALL TO authenticated
  USING (TRUE) WITH CHECK (TRUE);

-- ── Seed: approved 9-section landing page ──────────────────────────────────────
-- Display orders use multiples of 10 to allow insertion without renumbering.

INSERT INTO landing_page_sections
  (section_type, section_name, display_order, is_enabled, is_published, config)
VALUES
  (
    'hero', 'Hero', 10, TRUE, TRUE,
    '{"headline":"Expert Home Services, On Demand","subheadline":"Trusted professionals for all your home needs — booked in minutes.","cta_primary_text":"Book Now","cta_secondary_text":"Explore Services"}'::jsonb
  ),
  (
    'service_grid', 'Our Services', 20, TRUE, TRUE,
    '{"title":"Our Services","show_see_all":true}'::jsonb
  ),
  (
    'sub_services', 'Sub Services', 30, TRUE, TRUE,
    '{"title":"Sub Services"}'::jsonb
  ),
  (
    'why_dodo', 'Why Choose DODO', 40, TRUE, TRUE,
    '{
      "title":"Why Choose DODO Booker?",
      "subtitle":"Everything you need for a seamless home services experience.",
      "items":[
        {"icon":"verified_user_rounded","title":"Verified Professionals","description":"Every service provider is background-checked and certified before joining our platform."},
        {"icon":"receipt_long_rounded","title":"Transparent Pricing","description":"No hidden charges — what you see is what you pay. Get instant quotes upfront."},
        {"icon":"lock_rounded","title":"Secure Booking","description":"Your payments and personal data are protected with bank-grade encryption."}
      ]
    }'::jsonb
  ),
  (
    'how_it_works', 'How DODO Booker Works', 50, TRUE, TRUE,
    '{
      "title":"How DODO Booker Works",
      "steps":[
        {"icon":"search_rounded","title":"Choose a Service","description":"Browse our wide range of professional home services and find exactly what you need."},
        {"icon":"access_time_rounded","title":"Pick a Time","description":"Select a date and time slot that works best for your schedule."},
        {"icon":"verified_user_rounded","title":"Book a Professional","description":"Get matched with a verified, background-checked professional near you."},
        {"icon":"check_circle_rounded","title":"Get It Done","description":"Relax while our expert handles the job to your complete satisfaction."}
      ]
    }'::jsonb
  ),
  (
    'special_offers', 'Special Offers', 60, TRUE, TRUE,
    '{}'::jsonb
  ),
  (
    'popular_near_you', 'Popular Near You', 70, TRUE, TRUE,
    '{"title":"Popular Near You","show_see_all":true}'::jsonb
  ),
  (
    'testimonials', 'Customer Reviews', 80, TRUE, TRUE,
    '{"title":"What Our Customers Say"}'::jsonb
  ),
  (
    'footer', 'Footer', 90, TRUE, TRUE,
    '{}'::jsonb
  );

-- ── Seed: future generic section types (disabled, not published) ───────────────

INSERT INTO landing_page_sections
  (section_type, section_name, display_order, is_enabled, is_published, config)
VALUES
  (
    'content_grid', 'Thoughtful Creations', 100, FALSE, FALSE,
    '{"title":"Thoughtful Creations","subtitle":"Carefully curated services for your home.","items":[]}'::jsonb
  ),
  (
    'promo_banner', 'Promotional Banner', 110, FALSE, FALSE,
    '{"title":"Special Promotion","subtitle":"Limited time offer — book now and save.","cta_text":"Learn More","cta_url":"/"}'::jsonb
  ),
  (
    'faq', 'FAQ', 120, FALSE, FALSE,
    '{"title":"Frequently Asked Questions","items":[]}'::jsonb
  ),
  (
    'cta', 'Get Started', 130, FALSE, FALSE,
    '{"title":"Ready to Get Started?","subtitle":"Book your first professional home service today.","button_text":"Book Now","button_url":"/"}'::jsonb
  );
