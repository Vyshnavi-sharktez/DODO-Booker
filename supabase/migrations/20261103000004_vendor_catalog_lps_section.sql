-- ── Landing Page CMS: vendor_catalog section seed row ────────────────────────
--
-- Inserts the vendor_catalog section into landing_page_sections so the admin
-- panel can enable, reorder and publish it like any other section.
-- Starts disabled + unpublished; admin enables it explicitly.
-- ON CONFLICT DO NOTHING is safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.landing_page_sections
  (section_type, section_name, display_order, is_enabled, is_published, config)
SELECT 'vendor_catalog', 'Vendor Catalog Services', 140, false, false,
       '{"title": "Vendor Services"}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM public.landing_page_sections WHERE section_type = 'vendor_catalog'
);
