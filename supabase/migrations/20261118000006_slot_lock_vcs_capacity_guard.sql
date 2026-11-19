-- Migration: 20261118000006_slot_lock_vcs_capacity_guard.sql
--
-- Adds a capacity guard for VCS (catalog_vendor) checkout locks.
-- Previously lock_slot inserted a VCS lock with no capacity check, so two
-- concurrent customers could both receive a valid lock UUID and both proceed
-- to payment for the same vendor + slot even when max_bookings_per_slot = 1.
--
-- Fix: before inserting a VCS checkout lock, check
--   confirmed_bookings + active_checkout_locks >= max_bookings_per_slot
-- and return NULL (slot full) if the slot is already at capacity.
-- Max is read from catalog_node_configs(module='scheduling') with global
-- fallback to 5.

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

  -- ── Capacity guard: VCS (catalog_vendor) checkout locks ───────────────────
  -- vendor_id NOT NULL + service_id NOT NULL + mode_id NULL = VCS scope
  IF p_lock_type = 'checkout'
     AND p_vendor_id IS NOT NULL
     AND p_service_id IS NOT NULL
     AND p_mode_id IS NULL THEN

    -- max from catalog_node_configs scheduling module; default 5
    SELECT (config->>'max_bookings_per_slot')::INT INTO v_max
    FROM   catalog_node_configs
    WHERE  custom_service_id = p_service_id
      AND  module = 'scheduling';

    IF NOT FOUND OR v_max IS NULL THEN v_max := 5; END IF;

    -- Confirmed bookings for this vendor + VCS service + date + slot
    SELECT COUNT(*) INTO v_booked
    FROM   bookings b
    JOIN   booking_items bi ON bi.booking_id = b.id
    WHERE  bi.custom_service_id = p_service_id
      AND  b.vendor_id          = p_vendor_id
      AND  b.service_date       = p_service_date
      AND  b.scheduled_time     = p_slot_time
      AND  b.status NOT IN ('cancelled', 'rejected');

    -- Active checkout locks for this vendor + VCS service + date + slot
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

  -- ── Capacity guard: regular catalog service checkout locks ─────────────────
  -- vendor_id NULL + service_id NOT NULL + mode_id NULL = regular service scope
  IF p_lock_type = 'checkout'
     AND p_vendor_id IS NULL
     AND p_service_id IS NOT NULL
     AND p_mode_id IS NULL THEN

    SELECT max_bookings_per_slot INTO v_max
    FROM   service_scheduling WHERE service_id = p_service_id;

    IF NOT FOUND OR v_max IS NULL THEN
      SELECT max_bookings_per_slot INTO v_max
      FROM   global_scheduling LIMIT 1;
    END IF;

    IF v_max IS NULL THEN v_max := 5; END IF;

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
