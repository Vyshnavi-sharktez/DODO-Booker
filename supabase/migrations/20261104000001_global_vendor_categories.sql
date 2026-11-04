-- ── Global Vendor Categories ──────────────────────────────────────────────────
-- Makes vendor_categories a globally shared pool. When any vendor creates a
-- root category, it becomes available to all other vendors for service tagging.
--
-- Changes:
--  1. Drop per-vendor unique constraint (vendor_id, name)
--  2. Add global normalized-name unique index (case + whitespace insensitive)
--  3. Recreate get_my_vendor_categories() to return ALL global categories,
--     with service_count scoped to the calling vendor
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Drop the per-vendor uniqueness constraint
ALTER TABLE vendor_categories
  DROP CONSTRAINT IF EXISTS vendor_categories_unique_name;

-- 2. Global normalized-name unique index
--    Normalises: trim, collapse internal whitespace, lowercase
CREATE UNIQUE INDEX IF NOT EXISTS idx_vendor_categories_name_global_unique
  ON vendor_categories (
    LOWER(TRIM(REGEXP_REPLACE(name, '\s+', ' ', 'g')))
  );

-- 3. Recreate get_my_vendor_categories() to return all global categories.
--    service_count reflects only the calling vendor's services per category.

DROP FUNCTION IF EXISTS get_my_vendor_categories();

CREATE FUNCTION get_my_vendor_categories()
RETURNS TABLE (
  id            UUID,
  name          TEXT,
  icon_url      TEXT,
  service_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    vc.id,
    vc.name,
    vc.icon_url,
    COUNT(vsr.id) AS service_count
  FROM vendor_categories vc
  LEFT JOIN vendor_service_requests vsr
         ON vsr.vendor_category_id = vc.id
        AND vsr.vendor_id IN (
              SELECT id FROM vendors WHERE auth_user_id = auth.uid()
            )
        AND vsr.request_type = 'new_service'
        AND vsr.status       IN ('pending', 'completed', 'needs_catalog')
        AND vsr.is_active    = true
  GROUP BY vc.id, vc.name, vc.icon_url, vc.created_at
  ORDER BY vc.created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION get_my_vendor_categories() TO authenticated;
