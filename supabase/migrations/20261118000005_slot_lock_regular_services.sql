-- Migration: 20261118000005_slot_lock_regular_services.sql
--
-- Extends the slot-locking system to cover regular (non-VCS, non-InstaHelp)
-- catalog service bookings.
--
-- Problem: slot_locks previously required a vendor_id (NOT NULL), so checkout
-- locks could only be placed for VCS and InstaHelp flows. For regular services
-- with max_bookings_per_slot = 1, two customers could simultaneously reach
-- payment for the same slot because no lock was placed during checkout.
--
-- Solution:
--   1. Make vendor_id nullable — regular service locks have no vendor at
--      checkout time (vendor is assigned after booking is confirmed).
--   2. Add an index for the new NULL-vendor query path.
--   3. Extend lock_slot capacity guard to handle regular services, reading
--      max_bookings_per_slot from service_scheduling → global_scheduling.
--   4. Update rejection trigger to also lock regular service slots on rejection.

-- ── 1. Make vendor_id nullable ────────────────────────────────────────────────

ALTER TABLE slot_locks ALTER COLUMN vendor_id DROP NOT NULL;

-- ── 2. Index for regular-service locks (vendor_id IS NULL) ───────────────────

CREATE INDEX IF NOT EXISTS idx_slot_locks_regular
  ON slot_locks(service_id, service_date, slot_time, expires_at)
  WHERE vendor_id IS NULL AND service_id IS NOT NULL;

-- ── 3. Updated lock_slot with regular-service capacity guard ─────────────────
--
-- p_vendor_id is now optional (DEFAULT NULL).
-- Called with vendor_id=NULL for regular catalog services.
-- Called with vendor_id set for VCS and InstaHelp (no behaviour change there).

DROP FUNCTION IF EXISTS lock_slot(UUID, DATE, TEXT, TEXT, UUID, UUID, UUID, UUID, UUID);

CREATE OR REPLACE FUNCTION lock_slot(
  p_service_date DATE,
  p_slot_time    TEXT,
  p_lock_type    TEXT,
  p_vendor_id    UUID     DEFAULT NULL,
  p_mode_id      UUID     DEFAULT NULL,
  p_duration_id  UUID     DEFAULT NULL,
  p_service_id   UUID     DEFAULT NULL,
  p_customer_id  UUID     DEFAULT NULL,
  p_booking_id   UUID     DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_value   INT;
  v_unit    TEXT;
  v_seconds INT;
  v_lock_id UUID;
  v_max     INT;
  v_booked  INT;
  v_locked  INT;
BEGIN
  -- ── Serialize concurrent calls for the same slot ───────────────────────────
  PERFORM pg_advisory_xact_lock(
    hashtext(
      COALESCE(p_vendor_id::text, 'nil')
      || '|' || p_service_date::text
      || '|' || p_slot_time
      || '|' || COALESCE(p_mode_id::text,    '')
      || '|' || COALESCE(p_duration_id::text, '')
      || '|' || COALESCE(p_service_id::text,  '')
    )
  );

  -- ── Read hold duration from settings ──────────────────────────────────────
  IF p_lock_type = 'checkout' THEN
    SELECT COALESCE(setting_value, '5')::INT
    INTO   v_value
    FROM   settings WHERE setting_key = 'slot_checkout_hold_value';

    SELECT COALESCE(setting_value, 'minutes')
    INTO   v_unit
    FROM   settings WHERE setting_key = 'slot_checkout_hold_unit';
  ELSE
    SELECT COALESCE(setting_value, '1')::INT
    INTO   v_value
    FROM   settings WHERE setting_key = 'slot_rejection_release_value';

    SELECT COALESCE(setting_value, 'minutes')
    INTO   v_unit
    FROM   settings WHERE setting_key = 'slot_rejection_release_unit';
  END IF;

  v_seconds := v_value * CASE v_unit
    WHEN 'hours'   THEN 3600
    WHEN 'minutes' THEN 60
    ELSE 1
  END;

  -- ── Capacity guard: InstaHelp checkout locks ───────────────────────────────
  IF p_lock_type = 'checkout' AND p_mode_id IS NOT NULL AND p_duration_id IS NOT NULL THEN
    SELECT COALESCE(max_bookings_per_slot, 1) INTO v_max
    FROM   instahelp_durations WHERE id = p_duration_id;

    IF NOT FOUND THEN v_max := 1; END IF;

    SELECT COUNT(*) INTO v_booked
    FROM   bookings b
    JOIN   instahelp_bookings ib ON ib.booking_id = b.id
    WHERE  ib.mode_id       = p_mode_id
      AND  ib.duration_id   = p_duration_id
      AND  b.service_date   = p_service_date
      AND  b.scheduled_time = p_slot_time
      AND  b.status NOT IN ('cancelled', 'rejected');

    SELECT COUNT(*) INTO v_locked
    FROM   slot_locks
    WHERE  mode_id      = p_mode_id
      AND  duration_id  = p_duration_id
      AND  service_date = p_service_date
      AND  slot_time    = p_slot_time
      AND  lock_type    = 'checkout'
      AND  expires_at   > NOW();

    IF v_booked + v_locked >= v_max THEN RETURN NULL; END IF;
  END IF;

  -- ── Capacity guard: regular catalog service checkout locks ─────────────────
  -- (vendor_id IS NULL = regular service; no VCS, no InstaHelp)
  IF p_lock_type = 'checkout'
     AND p_vendor_id IS NULL
     AND p_service_id IS NOT NULL
     AND p_mode_id IS NULL THEN

    -- max_bookings_per_slot: service_scheduling → global_scheduling → 5
    SELECT max_bookings_per_slot INTO v_max
    FROM   service_scheduling WHERE service_id = p_service_id;

    IF NOT FOUND OR v_max IS NULL THEN
      SELECT max_bookings_per_slot INTO v_max
      FROM   global_scheduling LIMIT 1;
    END IF;

    IF v_max IS NULL THEN v_max := 5; END IF;

    -- Active confirmed bookings for this service + date + slot
    SELECT COUNT(*) INTO v_booked
    FROM   bookings
    WHERE  service_id    = p_service_id
      AND  service_date  = p_service_date
      AND  scheduled_time = p_slot_time
      AND  status NOT IN ('cancelled', 'rejected');

    -- Active checkout locks for this service (no vendor)
    SELECT COUNT(*) INTO v_locked
    FROM   slot_locks
    WHERE  service_id   = p_service_id
      AND  vendor_id    IS NULL
      AND  service_date = p_service_date
      AND  slot_time    = p_slot_time
      AND  lock_type    = 'checkout'
      AND  expires_at   > NOW();

    IF v_booked + v_locked >= v_max THEN RETURN NULL; END IF;
  END IF;

  -- ── Insert the lock ────────────────────────────────────────────────────────
  INSERT INTO slot_locks (
    lock_type, vendor_id, service_date, slot_time,
    mode_id, duration_id, service_id,
    customer_id, booking_id,
    expires_at
  ) VALUES (
    p_lock_type, p_vendor_id, p_service_date, p_slot_time,
    p_mode_id, p_duration_id, p_service_id,
    p_customer_id, p_booking_id,
    NOW() + (v_seconds || ' seconds')::INTERVAL
  )
  RETURNING id INTO v_lock_id;

  RETURN v_lock_id;
END;
$$;

-- ── 4. Update rejection trigger to include regular service bookings ────────────
--
-- When a regular (non-InstaHelp, non-VCS) booking is rejected, place a
-- vendor-scoped rejection lock so the slot stays blocked for that vendor
-- during the reassignment cooldown.

CREATE OR REPLACE FUNCTION fn_booking_rejection_slot_lock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_mode_id     UUID;
  v_duration_id UUID;
  v_service_id  UUID;
BEGIN
  IF NEW.status <> 'rejected' OR OLD.status = 'rejected' THEN
    RETURN NEW;
  END IF;

  IF NEW.vendor_id IS NULL OR NEW.service_date IS NULL OR NEW.scheduled_time IS NULL THEN
    RETURN NEW;
  END IF;

  -- InstaHelp booking?
  SELECT mode_id, duration_id INTO v_mode_id, v_duration_id
  FROM   instahelp_bookings WHERE booking_id = NEW.id;

  IF FOUND THEN
    PERFORM lock_slot(
      NEW.service_date::DATE, NEW.scheduled_time, 'rejection',
      NEW.vendor_id, v_mode_id, v_duration_id, NULL, NULL, NEW.id
    );
    RETURN NEW;
  END IF;

  -- VCS (catalog_vendor) booking?
  IF NEW.booking_source = 'catalog_vendor' THEN
    SELECT service_id INTO v_service_id
    FROM   booking_items
    WHERE  booking_id = NEW.id AND service_id IS NOT NULL
    LIMIT  1;

    IF FOUND AND v_service_id IS NOT NULL THEN
      PERFORM lock_slot(
        NEW.service_date::DATE, NEW.scheduled_time, 'rejection',
        NEW.vendor_id, NULL, NULL, v_service_id, NULL, NEW.id
      );
    END IF;
    RETURN NEW;
  END IF;

  -- Regular catalog service booking: vendor-scoped rejection lock
  IF NEW.service_id IS NOT NULL THEN
    PERFORM lock_slot(
      NEW.service_date::DATE, NEW.scheduled_time, 'rejection',
      NEW.vendor_id, NULL, NULL, NEW.service_id, NULL, NEW.id
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_booking_rejection_slot_lock ON bookings;
CREATE TRIGGER trg_booking_rejection_slot_lock
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_booking_rejection_slot_lock();
