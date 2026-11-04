-- ── Admin-Managed Vendor Root Categories ────────────────────────────────────
--
-- Extends vendor_categories to support admin-owned shared root categories.
-- A NULL vendor_id marks an admin-created shared category; a UUID vendor_id
-- marks a vendor-created category (existing behaviour, unchanged).
--
-- Changes:
--  1. Make vendor_id nullable (NULL = admin-created shared category)
--  2. Add sort_order column for admin-controlled ordering
--  3. Recreate get_my_vendor_categories() — already returns all rows (no WHERE
--     on vendor_id); rebuilt explicitly to include NULL vendor_id rows and to
--     ensure service_count is scoped to the calling vendor
--  4. Admin SECURITY DEFINER RPCs:
--       admin_get_vendor_categories()
--       admin_create_vendor_category(name, icon_url, sort_order)
--       admin_update_vendor_category(id, name, icon_url, sort_order)
--       admin_check_vendor_category_deps(id)
--       admin_delete_vendor_category(id)
--       admin_reassign_vendor_category(from_id, to_id)
--
-- RLS note: existing vendor policies already block NULL vendor_id rows because
-- `NULL IN (SELECT id FROM vendors ...)` evaluates to NULL (falsy). No RLS
-- changes are required; admin write access is enforced via SECURITY DEFINER.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Make vendor_id nullable ────────────────────────────────────────────────

ALTER TABLE vendor_categories
  ALTER COLUMN vendor_id DROP NOT NULL;

-- ── 2. Add sort_order ─────────────────────────────────────────────────────────

ALTER TABLE vendor_categories
  ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

-- ── 3. Recreate get_my_vendor_categories() ───────────────────────────────────
-- Returns ALL global categories (admin + vendor created).
-- service_count is scoped to the calling vendor's services.

DROP FUNCTION IF EXISTS get_my_vendor_categories();

CREATE FUNCTION get_my_vendor_categories()
RETURNS TABLE (
  id            UUID,
  name          TEXT,
  icon_url      TEXT,
  sort_order    INTEGER,
  vendor_id     UUID,
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
    vc.sort_order,
    vc.vendor_id,
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
  GROUP BY vc.id, vc.name, vc.icon_url, vc.sort_order, vc.vendor_id, vc.created_at
  ORDER BY vc.sort_order ASC, vc.name ASC;
$$;

GRANT EXECUTE ON FUNCTION get_my_vendor_categories() TO authenticated;

-- ── 4a. admin_get_vendor_categories() ────────────────────────────────────────
-- Returns all categories with platform-wide service_count and vendor_count.
-- Restricted to authenticated admin users.

DROP FUNCTION IF EXISTS admin_get_vendor_categories();

CREATE FUNCTION admin_get_vendor_categories()
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
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()) THEN
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

-- ── 4b. admin_create_vendor_category() ───────────────────────────────────────

DROP FUNCTION IF EXISTS admin_create_vendor_category(TEXT, TEXT, INTEGER);

CREATE FUNCTION admin_create_vendor_category(
  p_name       TEXT,
  p_icon_url   TEXT    DEFAULT NULL,
  p_sort_order INTEGER DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  INSERT INTO vendor_categories (vendor_id, name, icon_url, sort_order)
  VALUES (NULL, TRIM(p_name), p_icon_url, p_sort_order)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_create_vendor_category(TEXT, TEXT, INTEGER) TO authenticated;

-- ── 4c. admin_update_vendor_category() ───────────────────────────────────────

DROP FUNCTION IF EXISTS admin_update_vendor_category(UUID, TEXT, TEXT, INTEGER);

CREATE FUNCTION admin_update_vendor_category(
  p_id         UUID,
  p_name       TEXT,
  p_icon_url   TEXT    DEFAULT NULL,
  p_sort_order INTEGER DEFAULT 0
)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE vendor_categories
     SET name       = TRIM(p_name),
         icon_url   = p_icon_url,
         sort_order = p_sort_order
   WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Category % not found', p_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_vendor_category(UUID, TEXT, TEXT, INTEGER) TO authenticated;

-- ── 4d. admin_check_vendor_category_deps() ───────────────────────────────────
-- Returns dependency counts for a category before deletion.
--   active_service_count : live customer-facing services (completed + is_active)
--   total_service_count  : all non-rejected, non-deleted VSR rows using this category
--   vendor_count         : distinct vendors with any VSR in this category

DROP FUNCTION IF EXISTS admin_check_vendor_category_deps(UUID);

CREATE FUNCTION admin_check_vendor_category_deps(p_id UUID)
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
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()) THEN
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

-- ── 4e. admin_reassign_vendor_category() ─────────────────────────────────────
-- Moves all vendor_service_requests from p_from_id to p_to_id.
-- Used before deletion to safely migrate services to another category.

DROP FUNCTION IF EXISTS admin_reassign_vendor_category(UUID, UUID);

CREATE FUNCTION admin_reassign_vendor_category(
  p_from_id UUID,
  p_to_id   UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_from_id = p_to_id THEN
    RAISE EXCEPTION 'Source and target categories must differ';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM vendor_categories WHERE id = p_to_id) THEN
    RAISE EXCEPTION 'Target category % not found', p_to_id;
  END IF;

  UPDATE vendor_service_requests
     SET vendor_category_id = p_to_id
   WHERE vendor_category_id = p_from_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_reassign_vendor_category(UUID, UUID) TO authenticated;

-- ── 4f. admin_delete_vendor_category() ───────────────────────────────────────
-- Hard-deletes a category. Fails if any non-deleted VSR rows still reference it
-- (call admin_reassign_vendor_category first to clear dependencies).
-- Sets vendor_category_id = NULL on any remaining rows as a safety fallback.

DROP FUNCTION IF EXISTS admin_delete_vendor_category(UUID);

CREATE FUNCTION admin_delete_vendor_category(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_blocking BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT COUNT(*) INTO v_blocking
  FROM vendor_service_requests
  WHERE vendor_category_id = p_id
    AND request_type       = 'new_service'
    AND status NOT IN ('deleted', 'rejected');

  IF v_blocking > 0 THEN
    RAISE EXCEPTION
      'Cannot delete: % active service(s) still reference this category. Reassign them first.',
      v_blocking;
  END IF;

  -- Null-out any residual (deleted/rejected) VSR references before hard delete.
  UPDATE vendor_service_requests
     SET vendor_category_id = NULL
   WHERE vendor_category_id = p_id;

  DELETE FROM vendor_categories WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Category % not found', p_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_vendor_category(UUID) TO authenticated;
