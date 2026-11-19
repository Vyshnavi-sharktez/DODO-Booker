-- Migration: 20261118000009_slot_lock_node_config_max.sql
--
-- Root cause: admin sets max_bookings_per_slot=1 via Module Configuration,
-- which writes to catalog_node_configs (node_id = catalog_nodes.id).
-- lock_slot only read global_scheduling / service_scheduling, never
-- catalog_node_configs, so v_max was always the global default (5), and the
-- slot capacity guard never blocked a second booking.
--
-- Secondary bug: v_use_global is NULL when no service_scheduling row exists.
-- FALSE OR NULL = NULL in SQL, so the ELSIF branch was silently skipped.
--
-- Fix:
--   1. Check catalog_node_configs first (highest priority, same source as
--      resolve_catalog_module_config used by the slot display).
--   2. Fix the NULL guard: use COALESCE(v_use_global, FALSE).

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
  v_global_enabled BOOLEAN;
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
      AND  b.service_date       = p_service_date
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

    -- Priority 1: node-level config (Module Configuration in admin)
    -- This is the same source as resolve_catalog_module_config used by the
    -- slot display — must match or the lock fires at a different max than shown.
    SELECT (config->>'max_bookings_per_slot')::INT INTO v_node_max
    FROM   catalog_node_configs
    WHERE  node_id = p_service_id AND module = 'scheduling';

    IF FOUND AND v_node_max IS NOT NULL AND v_node_max > 0 THEN
      v_max := v_node_max;
    ELSE
      -- Priority 2: global_scheduling / service_scheduling fallback
      SELECT is_enabled, max_bookings_per_slot
      INTO   v_global_enabled, v_global_max
      FROM   global_scheduling LIMIT 1;

      SELECT max_bookings_per_slot, COALESCE(use_global_schedule, FALSE)
      INTO   v_svc_max, v_use_global
      FROM   service_scheduling
      WHERE  service_id = p_service_id;

      v_svc_found := FOUND;

      IF COALESCE(v_global_enabled, FALSE) OR COALESCE(v_use_global, FALSE) THEN
        v_max := COALESCE(v_global_max, 5);
      ELSIF v_svc_found THEN
        v_max := COALESCE(v_svc_max, 5);
      ELSE
        v_max := COALESCE(v_global_max, 5);
      END IF;
    END IF;

    SELECT COUNT(*) INTO v_booked
    FROM   bookings
    WHERE  service_id    = p_service_id
      AND  service_date  = p_service_date
      AND  scheduled_time = p_slot_time
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
