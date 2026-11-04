-- ── Fix: admin category RPCs — wrong admin identity column ───────────────────
-- admin_users.id is a generated UUID primary key (gen_random_uuid()).
-- The column linking to auth.users is auth_user_id, NOT id.
-- All six admin_*_vendor_category* RPCs used `WHERE id = auth.uid()`, which
-- never matches → always raised Unauthorized.
-- This migration recreates all six with the correct check:
--   WHERE auth_user_id = auth.uid() AND is_active = true
-- Also fixes the PL/pgSQL RETURNS TABLE output-variable ambiguity in
-- admin_get_vendor_categories() (admin_users.auth_user_id is unambiguous since
-- no output column is named auth_user_id).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── admin_get_vendor_categories ───────────────────────────────────────────────

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
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE admin_users.auth_user_id = auth.uid()
      AND admin_users.is_active    = true
  ) THEN
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

-- ── admin_create_vendor_category ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_create_vendor_category(
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
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE admin_users.auth_user_id = auth.uid()
      AND admin_users.is_active    = true
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  INSERT INTO vendor_categories (vendor_id, name, icon_url, sort_order)
  VALUES (NULL, TRIM(p_name), p_icon_url, p_sort_order)
  RETURNING vendor_categories.id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_create_vendor_category(TEXT, TEXT, INTEGER) TO authenticated;

-- ── admin_update_vendor_category ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_update_vendor_category(
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
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE admin_users.auth_user_id = auth.uid()
      AND admin_users.is_active    = true
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE vendor_categories
     SET name       = TRIM(p_name),
         icon_url   = p_icon_url,
         sort_order = p_sort_order
   WHERE vendor_categories.id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Category % not found', p_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_vendor_category(UUID, TEXT, TEXT, INTEGER) TO authenticated;

-- ── admin_check_vendor_category_deps ─────────────────────────────────────────

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
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE admin_users.auth_user_id = auth.uid()
      AND admin_users.is_active    = true
  ) THEN
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

-- ── admin_reassign_vendor_category ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_reassign_vendor_category(
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
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE admin_users.auth_user_id = auth.uid()
      AND admin_users.is_active    = true
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_from_id = p_to_id THEN
    RAISE EXCEPTION 'Source and target categories must differ';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM vendor_categories WHERE vendor_categories.id = p_to_id) THEN
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

-- ── admin_delete_vendor_category ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_delete_vendor_category(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_blocking BIGINT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE admin_users.auth_user_id = auth.uid()
      AND admin_users.is_active    = true
  ) THEN
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

  UPDATE vendor_service_requests
     SET vendor_category_id = NULL
   WHERE vendor_category_id = p_id;

  DELETE FROM vendor_categories WHERE vendor_categories.id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Category % not found', p_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_vendor_category(UUID) TO authenticated;
