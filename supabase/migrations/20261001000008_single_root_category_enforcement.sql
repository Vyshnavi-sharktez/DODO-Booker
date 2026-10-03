-- ============================================================
-- Single Root Category Enforcement on booking_items
-- ============================================================
-- A booking may only contain services that share the same root
-- catalog node.  "Root" = a catalog_nodes row with no parent in
-- catalog_node_relationships.
--
-- WHAT THIS MIGRATION DOES
--   1. Creates get_catalog_node_root_id(p_node_id uuid) → uuid
--      Walks the catalog_node_relationships parent chain upward
--      via a recursive CTE and returns the topmost ancestor id.
--      Returns NULL when p_node_id is NULL (custom services).
--
--   2. Creates fn_enforce_single_root_category()
--      BEFORE INSERT trigger function on booking_items.
--      Skips rows where service_id IS NULL (vendor custom services
--      are exempt from category enforcement).
--      Raises an exception when the new item's root category
--      differs from the root category already present in the
--      booking.
--
--   3. Attaches the trigger to booking_items.
--
-- SAFE TO RE-RUN: OR REPLACE / DROP IF EXISTS before CREATE
-- ============================================================


-- ============================================================
-- 1. Root-resolver function
-- ============================================================

CREATE OR REPLACE FUNCTION get_catalog_node_root_id(p_node_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH RECURSIVE ancestors AS (
    -- Base: start at the given node
    SELECT p_node_id AS node_id

    UNION ALL

    -- Step: walk one level up (first parent wins for shared nodes)
    SELECT r.parent_id
    FROM   catalog_node_relationships r
    JOIN   ancestors a ON a.node_id = r.child_id
  )
  -- The root is the ancestor that has no parent entry
  SELECT a.node_id
  FROM   ancestors a
  WHERE  NOT EXISTS (
    SELECT 1
    FROM   catalog_node_relationships r2
    WHERE  r2.child_id = a.node_id
  )
  LIMIT 1;
$$;


-- ============================================================
-- 2. Trigger function
-- ============================================================

CREATE OR REPLACE FUNCTION fn_enforce_single_root_category()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_root        uuid;
  v_existing_root   uuid;
BEGIN
  -- Custom / vendor services (service_id IS NULL) are exempt.
  IF NEW.service_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Resolve the root category for the incoming service.
  v_new_root := get_catalog_node_root_id(NEW.service_id);

  -- If the root is indeterminate, allow the insert.
  IF v_new_root IS NULL THEN
    RETURN NEW;
  END IF;

  -- Find the root category of any existing catalog-backed item
  -- already in this booking (ignoring custom-service rows).
  SELECT DISTINCT get_catalog_node_root_id(bi.service_id)
  INTO   v_existing_root
  FROM   booking_items bi
  WHERE  bi.booking_id  = NEW.booking_id
    AND  bi.service_id IS NOT NULL
  LIMIT 1;

  IF v_existing_root IS NOT NULL AND v_existing_root <> v_new_root THEN
    RAISE EXCEPTION
      'category_conflict: booking % already contains services from root category %. '
      'Cannot add service from root category %.',
      NEW.booking_id, v_existing_root, v_new_root
    USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;


-- ============================================================
-- 3. Attach trigger to booking_items
-- ============================================================

DROP TRIGGER IF EXISTS trg_enforce_single_root_category
  ON booking_items;

CREATE TRIGGER trg_enforce_single_root_category
  BEFORE INSERT ON booking_items
  FOR EACH ROW
  EXECUTE FUNCTION fn_enforce_single_root_category();
