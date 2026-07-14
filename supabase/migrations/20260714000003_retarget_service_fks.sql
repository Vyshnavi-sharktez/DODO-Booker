-- ============================================================
-- Migration: clean legacy data + retarget service FKs
-- ============================================================
-- State B: catalog rebuilt via UI — catalog_nodes.id ≠ services.id.
-- All existing bookings are test data; safe to delete entirely.
--
-- STEP 1: Delete all booking data in FK-safe order
-- STEP 2: Delete orphaned service-dependent rows
-- STEP 3: Retarget FK constraints from services to catalog_nodes
-- ============================================================


-- ══════════════════════════════════════════════════════════════
-- STEP 1: Delete all booking data
-- ══════════════════════════════════════════════════════════════
-- Child-first order. Dashboard-created tables are wrapped in
-- existence checks (booking_attribute_selections,
-- booking_status_history, booking_otp_verifications).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'booking_attribute_selections'
  ) THEN
    DELETE FROM booking_attribute_selections;
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'booking_status_history'
  ) THEN
    DELETE FROM booking_status_history;
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'booking_otp_verifications'
  ) THEN
    DELETE FROM booking_otp_verifications;
  END IF;
END;
$$;

-- customer_reviews FK → bookings
DELETE FROM customer_reviews;

-- booking_addons: addon_id → addons ON DELETE RESTRICT
-- Must be deleted before addons rows are removed.
DELETE FROM booking_addons;

DELETE FROM booking_images;
DELETE FROM booking_items;

-- Deleting bookings sets loyalty_transactions.booking_id = NULL (ON DELETE SET NULL).
DELETE FROM bookings;


-- ══════════════════════════════════════════════════════════════
-- STEP 2: Delete orphaned service-dependent rows
-- ══════════════════════════════════════════════════════════════
-- "Orphaned" = service_id holds a legacy services UUID that has
-- no matching catalog_nodes.id (State B: all 9 legacy UUIDs are
-- absent from catalog_nodes — catalog rebuilt with new UUIDs).

-- service_attribute_options (child) must precede service_attributes (parent).
-- The subquery references service_attributes, so guard both tables.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'service_attribute_options'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'service_attributes'
    ) THEN
      DELETE FROM service_attribute_options
      WHERE attribute_id IN (
        SELECT id FROM service_attributes
        WHERE service_id NOT IN (SELECT id FROM catalog_nodes)
      );
    ELSE
      DELETE FROM service_attribute_options;
    END IF;
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'service_attributes'
  ) THEN
    DELETE FROM service_attributes
    WHERE service_id NOT IN (SELECT id FROM catalog_nodes);
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'service_faqs'
  ) THEN
    DELETE FROM service_faqs
    WHERE service_id NOT IN (SELECT id FROM catalog_nodes);
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'service_add_ons'
  ) THEN
    DELETE FROM service_add_ons
    WHERE service_id NOT IN (SELECT id FROM catalog_nodes);
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'wishlists'
  ) THEN
    DELETE FROM wishlists
    WHERE service_id NOT IN (SELECT id FROM catalog_nodes);
  END IF;
END;
$$;

-- addons: 2 confirmed orphan rows; booking_addons already cleared above
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'addons'
  ) THEN
    DELETE FROM addons
    WHERE service_id NOT IN (SELECT id FROM catalog_nodes);
  END IF;
END;
$$;

-- vendor_services: 1 confirmed orphan row; rows with valid catalog_node
-- service_ids (if any) are kept and will satisfy the new FK below.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'vendor_services'
  ) THEN
    DELETE FROM vendor_services
    WHERE service_id NOT IN (SELECT id FROM catalog_nodes);
  END IF;
END;
$$;

-- cart_items: live DB confirmed FK cart_items.service_id → services.
-- Delete all rows whose service_id is a legacy UUID not in catalog_nodes.
DELETE FROM cart_items
WHERE service_id NOT IN (SELECT id FROM catalog_nodes);

-- package_services: live DB confirmed FK package_services.service_id → services.
-- No Dart code uses this table; all rows reference legacy service UUIDs.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'package_services'
  ) THEN
    DELETE FROM package_services
    WHERE service_id NOT IN (SELECT id FROM catalog_nodes);
  END IF;
END;
$$;

-- service_scheduling: NO FK constraint on service_id (UUID NOT NULL UNIQUE,
-- no REFERENCES clause). Rows hold legacy service UUIDs — stale data.
-- Delete them so the table is clean for catalog_node-based scheduling.
-- Global scheduling (global_scheduling table) is unaffected.
DELETE FROM service_scheduling
WHERE service_id NOT IN (SELECT id FROM catalog_nodes);


-- ══════════════════════════════════════════════════════════════
-- STEP 3: Retarget FK constraints from services to catalog_nodes
-- ══════════════════════════════════════════════════════════════
-- All dependent tables are now clean; every remaining service_id
-- value exists in catalog_nodes. New FKs will succeed.

-- ── service_faqs ──────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'service_faqs'
  ) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'service_faqs_service_id_fkey'
      AND table_name = 'service_faqs'
  ) THEN
    ALTER TABLE service_faqs DROP CONSTRAINT service_faqs_service_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'service_faqs_service_id_catalog_fkey'
      AND table_name = 'service_faqs'
  ) THEN
    ALTER TABLE service_faqs
      ADD CONSTRAINT service_faqs_service_id_catalog_fkey
        FOREIGN KEY (service_id) REFERENCES catalog_nodes(id) ON DELETE CASCADE;
  END IF;
END;
$$;

-- ── addons ────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'addons'
  ) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'addons_service_id_fkey'
      AND table_name = 'addons'
  ) THEN
    ALTER TABLE addons DROP CONSTRAINT addons_service_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'addons_service_id_catalog_fkey'
      AND table_name = 'addons'
  ) THEN
    ALTER TABLE addons
      ADD CONSTRAINT addons_service_id_catalog_fkey
        FOREIGN KEY (service_id) REFERENCES catalog_nodes(id) ON DELETE CASCADE;
  END IF;
END;
$$;

-- ── booking_items ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'booking_items_service_id_fkey'
      AND table_name = 'booking_items'
  ) THEN
    ALTER TABLE booking_items DROP CONSTRAINT booking_items_service_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'booking_items_service_id_catalog_fkey'
      AND table_name = 'booking_items'
  ) THEN
    ALTER TABLE booking_items
      ADD CONSTRAINT booking_items_service_id_catalog_fkey
        FOREIGN KEY (service_id) REFERENCES catalog_nodes(id) ON DELETE SET NULL;
  END IF;
END;
$$;

-- ── wishlists ─────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'wishlists'
  ) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'wishlists_service_id_fkey'
      AND table_name = 'wishlists'
  ) THEN
    ALTER TABLE wishlists DROP CONSTRAINT wishlists_service_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'wishlists_service_id_catalog_fkey'
      AND table_name = 'wishlists'
  ) THEN
    ALTER TABLE wishlists
      ADD CONSTRAINT wishlists_service_id_catalog_fkey
        FOREIGN KEY (service_id) REFERENCES catalog_nodes(id) ON DELETE CASCADE;
  END IF;
END;
$$;

-- ── service_attributes ────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'service_attributes'
  ) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'service_attributes_service_id_fkey'
      AND table_name = 'service_attributes'
  ) THEN
    ALTER TABLE service_attributes DROP CONSTRAINT service_attributes_service_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'service_attributes_service_id_catalog_fkey'
      AND table_name = 'service_attributes'
  ) THEN
    ALTER TABLE service_attributes
      ADD CONSTRAINT service_attributes_service_id_catalog_fkey
        FOREIGN KEY (service_id) REFERENCES catalog_nodes(id) ON DELETE CASCADE;
  END IF;
END;
$$;

-- ── vendor_services ───────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'vendor_services'
  ) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'vendor_services_service_id_fkey'
      AND table_name = 'vendor_services'
  ) THEN
    ALTER TABLE vendor_services DROP CONSTRAINT vendor_services_service_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'vendor_services_service_id_catalog_fkey'
      AND table_name = 'vendor_services'
  ) THEN
    ALTER TABLE vendor_services
      ADD CONSTRAINT vendor_services_service_id_catalog_fkey
        FOREIGN KEY (service_id) REFERENCES catalog_nodes(id) ON DELETE CASCADE;
  END IF;
END;
$$;

-- ── cart_items ────────────────────────────────────────────────────────────────
-- Dashboard-created FK name may differ from migration-created convention.
-- Drop any FK from cart_items.service_id → services dynamically, then add new.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT tc.constraint_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
     AND kcu.table_schema = 'public'
     AND kcu.table_name   = 'cart_items'
     AND kcu.column_name  = 'service_id'
    JOIN information_schema.referential_constraints rc
      ON rc.constraint_name = tc.constraint_name
     AND rc.constraint_schema = 'public'
    JOIN information_schema.table_constraints ccu
      ON ccu.constraint_name = rc.unique_constraint_name
     AND ccu.table_name      = 'services'
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema    = 'public'
      AND tc.table_name      = 'cart_items'
  LOOP
    EXECUTE format('ALTER TABLE cart_items DROP CONSTRAINT %I', r.constraint_name);
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
     AND kcu.table_name = 'cart_items' AND kcu.column_name = 'service_id'
    JOIN information_schema.referential_constraints rc
      ON rc.constraint_name = tc.constraint_name
    JOIN information_schema.table_constraints ccu
      ON ccu.constraint_name = rc.unique_constraint_name
     AND ccu.table_name = 'catalog_nodes'
    WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_name = 'cart_items'
  ) THEN
    ALTER TABLE cart_items
      ADD CONSTRAINT cart_items_service_id_catalog_fkey
        FOREIGN KEY (service_id) REFERENCES catalog_nodes(id) ON DELETE CASCADE;
  END IF;
END;
$$;

-- ── package_services ──────────────────────────────────────────────────────────
-- Dashboard-created; same dynamic drop pattern.
DO $$
DECLARE
  r RECORD;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'package_services'
  ) THEN
    RETURN;
  END IF;

  FOR r IN
    SELECT tc.constraint_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
     AND kcu.table_schema = 'public'
     AND kcu.table_name   = 'package_services'
     AND kcu.column_name  = 'service_id'
    JOIN information_schema.referential_constraints rc
      ON rc.constraint_name = tc.constraint_name
     AND rc.constraint_schema = 'public'
    JOIN information_schema.table_constraints ccu
      ON ccu.constraint_name = rc.unique_constraint_name
     AND ccu.table_name      = 'services'
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema    = 'public'
      AND tc.table_name      = 'package_services'
  LOOP
    EXECUTE format('ALTER TABLE package_services DROP CONSTRAINT %I', r.constraint_name);
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
     AND kcu.table_name = 'package_services' AND kcu.column_name = 'service_id'
    JOIN information_schema.referential_constraints rc
      ON rc.constraint_name = tc.constraint_name
    JOIN information_schema.table_constraints ccu
      ON ccu.constraint_name = rc.unique_constraint_name
     AND ccu.table_name = 'catalog_nodes'
    WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_name = 'package_services'
  ) THEN
    ALTER TABLE package_services
      ADD CONSTRAINT package_services_service_id_catalog_fkey
        FOREIGN KEY (service_id) REFERENCES catalog_nodes(id) ON DELETE CASCADE;
  END IF;
END;
$$;

-- ── vendors.category_id ───────────────────────────────────────────────────────
-- Drop FK only (column kept; commission_rules uses category UUID as lookup key)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'vendors_category_id_fkey'
      AND table_name = 'vendors'
  ) THEN
    ALTER TABLE vendors DROP CONSTRAINT vendors_category_id_fkey;
  END IF;
END;
$$;
