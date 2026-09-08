-- ── Vendor Custom Service: FAQs and Reviews ──────────────────────────────────────
--
-- 1. service_faqs: service_id made nullable; custom_service_id FK added to
--    vendor_service_requests; CHECK guarantees exactly one is set per row.
--    Existing catalog-node FAQ rows are unaffected (service_id stays set,
--    custom_service_id stays NULL).
--
-- 2. vendor_service_requests: denormalised rating + review_count added,
--    mirroring catalog_nodes.rating / review_count. Updated by Dart after each
--    review submission (same pattern as catalog_nodes).
--
-- 3. search_vendor_custom_services RPC: returns rating + review_count so the
--    customer detail sheet can display live ratings without a second query.

-- ────────────────────────────────────────────────────────────────────────────────
-- 1. service_faqs — dual-service support
-- ────────────────────────────────────────────────────────────────────────────────

-- Allow service_id to be NULL so a row belongs to either:
--   catalog node: service_id IS NOT NULL, custom_service_id IS NULL
--   vendor custom service: service_id IS NULL, custom_service_id IS NOT NULL
ALTER TABLE service_faqs
  ALTER COLUMN service_id DROP NOT NULL;

ALTER TABLE service_faqs
  ADD COLUMN IF NOT EXISTS custom_service_id UUID
    REFERENCES vendor_service_requests(id) ON DELETE CASCADE;

-- Partial index — only indexes rows where custom_service_id is set.
CREATE INDEX IF NOT EXISTS idx_service_faqs_custom_service_id
  ON service_faqs (custom_service_id)
  WHERE custom_service_id IS NOT NULL;

-- Exactly-one-of constraint (guarded for idempotent re-runs).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema    = 'public'
      AND table_name      = 'service_faqs'
      AND constraint_name = 'service_faqs_one_service_check'
  ) THEN
    ALTER TABLE service_faqs
      ADD CONSTRAINT service_faqs_one_service_check
      CHECK (
        (service_id IS NOT NULL AND custom_service_id IS NULL) OR
        (service_id IS NULL     AND custom_service_id IS NOT NULL)
      );
  END IF;
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────────
-- 2. vendor_service_requests — denormalised rating fields
-- ────────────────────────────────────────────────────────────────────────────────

ALTER TABLE vendor_service_requests
  ADD COLUMN IF NOT EXISTS rating       NUMERIC(3,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_count INTEGER      NOT NULL DEFAULT 0;

-- ────────────────────────────────────────────────────────────────────────────────
-- 3. search_vendor_custom_services — expose rating + review_count
-- ────────────────────────────────────────────────────────────────────────────────

-- DROP first because CREATE OR REPLACE cannot change the RETURNS TABLE column list.
-- The original function (7 columns) is incompatible with the new signature (9 columns).
-- SECURITY DEFINER, search_path, and default PUBLIC EXECUTE grant are preserved on
-- the new function exactly as they were on the original.
DROP FUNCTION IF EXISTS search_vendor_custom_services(TEXT);

CREATE FUNCTION search_vendor_custom_services(p_query TEXT)
RETURNS TABLE (
  id            UUID,
  service_name  TEXT,
  description   TEXT,
  active_price  NUMERIC,
  image_url     TEXT,
  vendor_id     UUID,
  vendor_name   TEXT,
  rating        NUMERIC,
  review_count  INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    vsr.id,
    vsr.service_name,
    vsr.description,
    vsr.active_price,
    vsr.image_url,
    vsr.vendor_id,
    v.business_name AS vendor_name,
    vsr.rating,
    vsr.review_count
  FROM vendor_service_requests vsr
  JOIN vendors v ON v.id = vsr.vendor_id
  WHERE vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND v.is_active      = true
    AND (
      vsr.service_name ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY vsr.service_name
  LIMIT 50;
$$;
