-- Migration: 20261117000002_slot_lock_race_fix.sql
--
-- Fixes a TOCTOU race condition in lock_slot where two concurrent callers
-- could both pass the capacity check before either committed, resulting in
-- both receiving a lock and creating a double booking.
--
-- Fix: acquire a per-slot advisory transaction lock at the top of the
-- function. pg_advisory_xact_lock serializes concurrent calls for the same
-- slot key; the lock is released automatically when the transaction ends.

CREATE OR REPLACE FUNCTION lock_slot(
  p_vendor_id    UUID,
  p_service_date DATE,
  p_slot_time    TEXT,
  p_lock_type    TEXT,
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
  v_value       INT;
  v_unit        TEXT;
  v_seconds     INT;
  v_lock_id     UUID;
  v_max         INT;
  v_booked      INT;
  v_locked      INT;
BEGIN
  -- ── Serialize concurrent calls for the same slot ───────────────────────────
  -- Advisory lock key is a hash of (vendor, date, slot, mode, duration).
  -- Any second caller for the identical slot waits here until the first
  -- transaction commits or rolls back, eliminating the check-then-insert race.
  PERFORM pg_advisory_xact_lock(
    hashtext(
      p_vendor_id::text
      || '|' || p_service_date::text
      || '|' || p_slot_time
      || '|' || COALESCE(p_mode_id::text,     '')
      || '|' || COALESCE(p_duration_id::text,  '')
      || '|' || COALESCE(p_service_id::text,   '')
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

  -- ── Capacity guard (checkout + InstaHelp only) ─────────────────────────────
  IF p_lock_type = 'checkout' AND p_mode_id IS NOT NULL AND p_duration_id IS NOT NULL THEN
    SELECT COALESCE(max_bookings_per_slot, 1)
    INTO   v_max
    FROM   instahelp_durations
    WHERE  id = p_duration_id;

    IF NOT FOUND THEN v_max := 1; END IF;

    SELECT COUNT(*)
    INTO   v_booked
    FROM   bookings b
    JOIN   instahelp_bookings ib ON ib.booking_id = b.id
    WHERE  ib.mode_id       = p_mode_id
      AND  ib.duration_id   = p_duration_id
      AND  b.service_date   = p_service_date
      AND  b.scheduled_time = p_slot_time
      AND  b.status NOT IN ('cancelled', 'rejected');

    SELECT COUNT(*)
    INTO   v_locked
    FROM   slot_locks
    WHERE  mode_id      = p_mode_id
      AND  duration_id  = p_duration_id
      AND  service_date = p_service_date
      AND  slot_time    = p_slot_time
      AND  lock_type    = 'checkout'
      AND  expires_at   > NOW();

    IF v_booked + v_locked >= v_max THEN
      RETURN NULL;
    END IF;
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
