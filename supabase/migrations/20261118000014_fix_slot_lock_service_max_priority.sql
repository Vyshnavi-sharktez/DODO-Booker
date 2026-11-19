-- Migration: 20261118000014_fix_slot_lock_service_max_priority.sql
--
-- Root cause of "product level max not working":
--
--   When global_scheduling.is_enabled = TRUE, the ELSE fallback block in
--   lock_slot set v_max = global_max, completely ignoring any per-service
--   max_bookings_per_slot set via the Service Scheduling dialog
--   (service_scheduling table). The service max was only used when global
--   master was explicitly OFF.
--
-- Fix: service_scheduling.max_bookings_per_slot always takes priority over
-- global_scheduling.max_bookings_per_slot unless the service has opted into
-- global scheduling (use_global_schedule = TRUE). Global master ON/OFF
-- controls which time slots are available, not capacity limits.
--
-- Priority chain (most → least specific):
--   1. catalog_node_configs ancestor walk (Module Configuration in admin)
--   2. service_scheduling.max_bookings_per_slot (Service Scheduling dialog)
--   3. global_scheduling.max_bookings_per_slot
--   4. default 5

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
  v_use_global     BOOLEAN;
  v_svc_found      BOOLEAN := FALSE;
  v_node_max       INT;
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

  v_value   := COALESCE(v_value, 5);
  v_unit    := COALESCE(v_unit, 'minutes');

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

    -- Priority 1: catalog_node_configs ancestor walk (Module Configuration in admin).
    -- Checks the service node first (depth 0), then walks up to subcategory,
    -- category — same resolution as resolve_catalog_module_config step B.
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
      -- Highest priority: node-scoped config from Module Configuration.
      v_max := v_node_max;
    ELSE
      -- Priority 2: service_scheduling (set via Service Scheduling dialog).
      -- Priority 3: global_scheduling fallback.
      --
      -- service_scheduling.max_bookings_per_slot ALWAYS wins over global max
      -- unless the service explicitly opted into global scheduling
      -- (use_global_schedule = TRUE). The global master ON/OFF flag only
      -- controls which time slots are available, not per-slot capacity.
      SELECT max_bookings_per_slot, COALESCE(use_global_schedule, FALSE)
      INTO   v_svc_max, v_use_global
      FROM   service_scheduling
      WHERE  service_id = p_service_id;

      v_svc_found := FOUND;

      SELECT max_bookings_per_slot
      INTO   v_global_max
      FROM   global_scheduling LIMIT 1;

      IF v_svc_found AND v_svc_max IS NOT NULL AND NOT COALESCE(v_use_global, FALSE) THEN
        -- Service has its own capacity limit and has not opted into global.
        v_max := v_svc_max;
      ELSE
        -- Service opted into global, or has no row / no max set → use global.
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
