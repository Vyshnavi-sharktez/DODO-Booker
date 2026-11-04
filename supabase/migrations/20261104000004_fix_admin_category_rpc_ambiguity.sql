-- ── Fix: ambiguous column "id" in admin_get_vendor_categories ────────────────
-- In a PL/pgSQL RETURNS TABLE function, each output column name becomes an
-- implicit OUT variable. When the function declares `id UUID` in RETURNS TABLE,
-- `WHERE id = auth.uid()` is ambiguous between the OUT var and admin_users.id.
-- Fix: qualify as `admin_users.id` in every admin guard inside such functions.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_get_vendor_categories()
RETURNS TABLE (
  id            UUID,
  name          TEXT,
  icon_url      TEXT,
  sort_order    INTEGER,
  vendor_id     UUID,
  created_at    TIMESTAMPTZ,
  service_count BIGINT,
  vendor_count  BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE admin_users.id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT
    vc.id,
    vc.name,
    vc.icon_url,
    vc.sort_order,
    vc.vendor_id,
    vc.created_at,
    COUNT(DISTINCT vsr.id)        AS service_count,
    COUNT(DISTINCT vsr.vendor_id) AS vendor_count
  FROM vendor_categories vc
  LEFT JOIN vendor_service_requests vsr
         ON vsr.vendor_category_id = vc.id
        AND vsr.request_type       = 'new_service'
        AND vsr.status NOT IN ('deleted', 'rejected')
  GROUP BY vc.id, vc.name, vc.icon_url, vc.sort_order, vc.vendor_id, vc.created_at
  ORDER BY vc.sort_order ASC, vc.name ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_vendor_categories() TO authenticated;

-- admin_check_vendor_category_deps has no `id` output column but qualify anyway
-- for consistency and future safety.

CREATE OR REPLACE FUNCTION admin_check_vendor_category_deps(p_id UUID)
RETURNS TABLE (
  active_service_count BIGINT,
  total_service_count  BIGINT,
  vendor_count         BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE admin_users.id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT
    COUNT(*) FILTER (
      WHERE vsr.status = 'completed' AND vsr.is_active = true
    )                                                       AS active_service_count,
    COUNT(*) FILTER (
      WHERE vsr.status NOT IN ('deleted', 'rejected')
    )                                                       AS total_service_count,
    COUNT(DISTINCT vsr.vendor_id)                           AS vendor_count
  FROM vendor_service_requests vsr
  WHERE vsr.vendor_category_id = p_id
    AND vsr.request_type       = 'new_service';
END;
$$;

GRANT EXECUTE ON FUNCTION admin_check_vendor_category_deps(UUID) TO authenticated;
