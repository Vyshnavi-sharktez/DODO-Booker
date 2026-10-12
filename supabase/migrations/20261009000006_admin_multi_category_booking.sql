-- ============================================================
-- Admin Multi-Category Booking Support
-- ============================================================
-- Admin-created and admin-edited bookings are allowed to contain
-- services from different root catalog categories.
--
-- WHAT THIS MIGRATION DOES
--   1. Adds is_admin_booking (boolean, default false) to bookings.
--   2. Replaces fn_enforce_single_root_category() to skip the
--      single-root check when is_admin_booking = true.
--
-- Customer-created bookings are unaffected: the category
-- restriction remains in place for all non-admin bookings.
-- ============================================================


-- 1. Add flag column
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS is_admin_booking boolean NOT NULL DEFAULT false;


-- 2. Replace the category enforcement trigger function
CREATE OR REPLACE FUNCTION fn_enforce_single_root_category()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_root        uuid;
  v_existing_root   uuid;
  v_is_admin        boolean;
BEGIN
  -- Custom / vendor services (service_id IS NULL) are always exempt.
  IF NEW.service_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Admin bookings bypass the single-root-category restriction.
  SELECT is_admin_booking
  INTO   v_is_admin
  FROM   bookings
  WHERE  id = NEW.booking_id;

  IF v_is_admin IS TRUE THEN
    RETURN NEW;
  END IF;

  -- Resolve the root category for the incoming service.
  v_new_root := get_catalog_node_root_id(NEW.service_id);

  -- Indeterminate root: allow.
  IF v_new_root IS NULL THEN
    RETURN NEW;
  END IF;

  -- Find the root of any existing catalog-backed item in this booking.
  SELECT DISTINCT get_catalog_node_root_id(bi.service_id)
  INTO   v_existing_root
  FROM   booking_items bi
  WHERE  bi.booking_id = NEW.booking_id
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
