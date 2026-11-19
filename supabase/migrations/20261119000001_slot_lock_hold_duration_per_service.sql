-- Migration: 20261119000001_slot_lock_hold_duration_per_service.sql
--
-- Problem: lock_slot always reads slot checkout hold duration from the global
--   settings table, ignoring any service-level or category-level config.
--   The capacity (max_bookings_per_slot) already walks the ancestor chain since
--   migration 20261118000015, but the hold duration block was never updated.
--
-- Fix:
--   1. Add nullable checkout_hold_value / checkout_hold_unit columns to
--      service_scheduling so admins can set a per-service override.
--   2. For regular catalog services, lock_slot now resolves hold duration via:
--        a. catalog_node_configs ancestor walk  (config->>'checkout_hold_value',
--                                                config->>'checkout_hold_unit')
--        b. service_scheduling override columns
--        c. global settings fallback (unchanged behaviour for everything else)
--   InstaHelp and VCS locks continue to use the global settings only.

-- ── 1. Schema change ──────────────────────────────────────────────────────────

ALTER TABLE service_scheduling
  ADD COLUMN IF NOT EXISTS checkout_hold_value INT,
  ADD COLUMN IF NOT EXISTS checkout_hold_unit  TEXT
    CHECK (checkout_hold_unit IN ('seconds', 'minutes', 'hours'));

-- ── 2. Recreate lock_slot with per-service hold duration resolution ────────────

DROP FUNCTION IF EXISTS lock_slot(DATE, TEXT, TEXT, UUID, UUID, UUID, UUID, UUID, UUID);

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
  v_value          INT;
  v_unit           TEXT;
  v_seconds        INT;
  v_lock_id        UUID;
  v_max            INT;
  v_booked         INT;
  v_locked         INT;
  v_global_max     INT;
  v_svc_max        INT;
  v_svc_found      BOOLEAN := FALSE;
  v_node_max       INT;
  -- hold duration resolution
  v_node_hold_value INT;
  v_node_hold_unit  TEXT;
  v_svc_hold_value  INT;
  v_svc_hold_unit   TEXT;
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

  -- ── Read hold duration — global fallback first ────────────────────────────
  IF p_lock_type = 'checkout' THEN
    SELECT COALESCE(setting_value, '5')::INT INTO v_value
    FROM   settings WHERE setting_key = 'slot_checkout_hold_value';
    SELECT COALESCE(setting_value, 'minutes') INTO v_unit
    FROM   settings WHERE setting_key = 'slot_checkout_hold_unit';
  ELSE
    SELECT COALESCE(setting_value, '1')::INT INTO v_value
    FROM   settings WHERE setting_key = 'slot_rejection_release_value';
    SELECT COALESCE(setting_value, 'minutes') INTO v_unit
    FROM   settings WHERE setting_key = 'slot_rejection_release_unit';
  END IF;

  v_value := COALESCE(v_value, 5);
  v_unit  := COALESCE(v_unit, 'minutes');

  -- ── Per-service hold duration override (regular catalog services only) ─────
  -- Applies to checkout locks where p_service_id is known and this is not
  -- an InstaHelp (p_mode_id IS NULL) or VCS (p_vendor_id IS NULL) call.
  IF p_lock_type = 'checkout'
     AND p_service_id IS NOT NULL
     AND p_vendor_id  IS NULL
     AND p_mode_id    IS NULL THEN

    -- Priority 1: catalog_node_configs ancestor walk.
    SELECT
      (cnc.config->>'checkout_hold_value')::INT,
       cnc.config->>'checkout_hold_unit'
    INTO v_node_hold_value, v_node_hold_unit
    FROM (
      WITH RECURSIVE node_walk(id, depth) AS (
        SELECT p_service_id, 0
        UNION ALL
        SELECT r.parent_id, nw.depth + 1
        FROM   node_walk nw
        JOIN   catalog_node_relationships r ON r.child_id = nw.id
        WHERE  nw.depth < 10
      )
      SELECT id, depth FROM node_walk
    ) nw
    JOIN catalog_node_configs cnc
      ON  cnc.node_id         = nw.id
     AND  cnc.module          = 'scheduling'
     AND  cnc.relationship_id IS NULL
     AND  cnc.is_enabled      = true
     AND  cnc.config ? 'checkout_hold_value'
    ORDER BY nw.depth ASC
    LIMIT 1;

    IF FOUND AND v_node_hold_value IS NOT NULL AND v_node_hold_value > 0 THEN
      v_value := v_node_hold_value;
      v_unit  := COALESCE(v_node_hold_unit, 'minutes');
    ELSE
      -- Priority 2: service_scheduling override columns.
      SELECT checkout_hold_value, checkout_hold_unit
      INTO   v_svc_hold_value, v_svc_hold_unit
      FROM   service_scheduling
      WHERE  service_id = p_service_id;

      IF FOUND AND v_svc_hold_value IS NOT NULL AND v_svc_hold_value > 0 THEN
        v_value := v_svc_hold_value;
        v_unit  := COALESCE(v_svc_hold_unit, 'minutes');
      END IF;
      -- else: keep the global settings value read above
    END IF;
  END IF;

  v_seconds := v_value * CASE v_unit
    WHEN 'hours'   THEN 3600
    WHEN 'minutes' THEN 60
    ELSE 1
  END;

  -- ── Capacity guard: InstaHelp ──────────────────────────────────────────────
  IF p_lock_type = 'checkout' AND p_mode_id IS NOT NULL AND p_duration_id IS NOT NULL THEN
    SELECT COALESCE(max_bookings_per_slot, 1) INTO v_max
    FROM   instahelp_durations WHERE id = p_duration_id;
    IF NOT FOUND THEN v_max := 1; END IF;

    SELECT COUNT(*) INTO v_booked
    FROM   bookings b
    JOIN   instahelp_bookings ib ON ib.booking_id = b.id
    WHERE  ib.mode_id       = p_mode_id
      AND  ib.duration_id   = p_duration_id
      AND  b.service_date::DATE = p_service_date
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

  -- ── Capacity guard: VCS ────────────────────────────────────────────────────
  IF p_lock_type = 'checkout'
     AND p_vendor_id IS NOT NULL
     AND p_service_id IS NOT NULL
     AND p_mode_id IS NULL THEN

    SELECT (config->>'max_bookings_per_slot')::INT INTO v_max
    FROM   catalog_node_configs
    WHERE  custom_service_id = p_service_id AND module = 'scheduling';
    IF NOT FOUND OR v_max IS NULL THEN v_max := 5; END IF;

    SELECT COUNT(*) INTO v_booked
    FROM   bookings b
    JOIN   booking_items bi ON bi.booking_id = b.id
    WHERE  bi.custom_service_id = p_service_id
      AND  b.vendor_id          = p_vendor_id
      AND  b.service_date::DATE = p_service_date
      AND  b.scheduled_time     = p_slot_time
      AND  b.status NOT IN ('cancelled', 'rejected');

    SELECT COUNT(*) INTO v_locked
    FROM   slot_locks
    WHERE  service_id   = p_service_id
      AND  vendor_id    = p_vendor_id
      AND  service_date = p_service_date
      AND  slot_time    = p_slot_time
      AND  lock_type    = 'checkout'
      AND  expires_at   > NOW();

    IF v_booked + v_locked >= v_max THEN RETURN NULL; END IF;
  END IF;

  -- ── Capacity guard: regular catalog service ────────────────────────────────
  IF p_lock_type = 'checkout'
     AND p_vendor_id IS NULL
     AND p_service_id IS NOT NULL
     AND p_mode_id IS NULL THEN

    -- Priority 1: catalog_node_configs ancestor walk.
    SELECT (cnc.config->>'max_bookings_per_slot')::INT INTO v_node_max
    FROM (
      WITH RECURSIVE node_walk(id, depth) AS (
        SELECT p_service_id, 0
        UNION ALL
        SELECT r.parent_id, nw.depth + 1
        FROM   node_walk nw
        JOIN   catalog_node_relationships r ON r.child_id = nw.id
        WHERE  nw.depth < 10
      )
      SELECT id, depth FROM node_walk
    ) nw
    JOIN catalog_node_configs cnc
      ON  cnc.node_id         = nw.id
     AND  cnc.module          = 'scheduling'
     AND  cnc.relationship_id IS NULL
     AND  cnc.is_enabled      = true
    ORDER BY nw.depth ASC
    LIMIT 1;

    IF FOUND AND v_node_max IS NOT NULL AND v_node_max > 0 THEN
      v_max := v_node_max;
    ELSE
      -- Priority 2: service_scheduling.max_bookings_per_slot.
      SELECT max_bookings_per_slot
      INTO   v_svc_max
      FROM   service_scheduling
      WHERE  service_id = p_service_id;

      v_svc_found := FOUND;

      SELECT max_bookings_per_slot
      INTO   v_global_max
      FROM   global_scheduling LIMIT 1;

      IF v_svc_found AND v_svc_max IS NOT NULL AND v_svc_max > 0 THEN
        v_max := v_svc_max;
      ELSE
        v_max := COALESCE(v_global_max, 5);
      END IF;
    END IF;

    SELECT COUNT(*) INTO v_booked
    FROM   bookings
    WHERE  service_id         = p_service_id
      AND  service_date::DATE = p_service_date
      AND  scheduled_time     = p_slot_time
      AND  status NOT IN ('cancelled', 'rejected');

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

  -- ── Insert lock ───────────────────────────────────────────────────────────
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
