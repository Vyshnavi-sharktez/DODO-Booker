-- Migration: 20261117000001_slot_locking_system.sql
--
-- Implements a slot-locking system for InstaHelp scheduled bookings and
-- Vendor Catalog Service (VCS / catalog_vendor) bookings.
--
-- Problem: two customers could simultaneously select and book the same vendor
-- at the same time slot because there was no hold during checkout.
--
-- Solution (BookMyShow model):
--   1. When a customer hits "Book Now" / "Place Order", lock the slot for a
--      configurable hold duration (checkout hold).
--   2. If the customer abandons checkout, the lock expires automatically and
--      the slot becomes bookable again.
--   3. When a vendor rejects a booking, a separate rejection lock keeps the
--      slot unavailable for a configurable cooldown period.
--
-- Two admin-configurable settings:
--   slot_checkout_hold_value  / slot_checkout_hold_unit   (default: 5 minutes)
--   slot_rejection_release_value / slot_rejection_release_unit (default: 1 minute)

-- ── 1. slot_locks table ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS slot_locks (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  lock_type    TEXT        NOT NULL CHECK (lock_type IN ('checkout','rejection')),
  vendor_id    UUID        NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  service_date DATE        NOT NULL,
  slot_time    TEXT        NOT NULL,
  -- InstaHelp scope (both set for InstaHelp locks)
  mode_id      UUID        REFERENCES instahelp_modes(id) ON DELETE CASCADE,
  duration_id  UUID,
  -- VCS scope (set for catalog_vendor locks)
  service_id   UUID,
  -- Metadata
  customer_id  UUID,
  booking_id   UUID        REFERENCES bookings(id) ON DELETE CASCADE,
  locked_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at   TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_slot_locks_ih
  ON slot_locks(mode_id, duration_id, service_date, slot_time, expires_at)
  WHERE mode_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_slot_locks_vcs
  ON slot_locks(service_id, vendor_id, service_date, slot_time, expires_at)
  WHERE service_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_slot_locks_expiry
  ON slot_locks(expires_at);

-- ── 2. Settings defaults ──────────────────────────────────────────────────────

INSERT INTO settings (setting_key, setting_value) VALUES
  ('slot_checkout_hold_value',      '5'),
  ('slot_checkout_hold_unit',       'minutes'),
  ('slot_rejection_release_value',  '1'),
  ('slot_rejection_release_unit',   'minutes')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 3. lock_slot RPC ──────────────────────────────────────────────────────────
--
-- Called by the customer app when entering checkout (type='checkout') or
-- by the rejection trigger (type='rejection').
-- Returns the new lock's UUID, or NULL if the slot is already at capacity.

CREATE OR REPLACE FUNCTION lock_slot(
  p_vendor_id    UUID,
  p_service_date DATE,
  p_slot_time    TEXT,
  p_lock_type    TEXT,         -- 'checkout' | 'rejection'
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
  -- ── Read duration from settings ────────────────────────────────────────────
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
    ELSE 1  -- seconds
  END;

  -- ── Capacity guard for InstaHelp checkout locks ────────────────────────────
  -- Skip guard for rejection locks (they always apply) and VCS (service-level).
  IF p_lock_type = 'checkout' AND p_mode_id IS NOT NULL AND p_duration_id IS NOT NULL THEN
    -- Get slot capacity
    SELECT COALESCE(max_bookings_per_slot, 1)
    INTO   v_max
    FROM   instahelp_durations
    WHERE  id = p_duration_id;

    IF NOT FOUND THEN v_max := 1; END IF;

    -- Count existing non-cancelled/rejected bookings for this slot
    SELECT COUNT(*)
    INTO   v_booked
    FROM   bookings b
    JOIN   instahelp_bookings ib ON ib.booking_id = b.id
    WHERE  ib.mode_id       = p_mode_id
      AND  ib.duration_id   = p_duration_id
      AND  b.service_date   = p_service_date
      AND  b.scheduled_time = p_slot_time
      AND  b.status NOT IN ('cancelled', 'rejected');

    -- Count active checkout locks for this slot
    SELECT COUNT(*)
    INTO   v_locked
    FROM   slot_locks
    WHERE  mode_id      = p_mode_id
      AND  duration_id  = p_duration_id
      AND  service_date = p_service_date
      AND  slot_time    = p_slot_time
      AND  lock_type    = 'checkout'
      AND  expires_at   > NOW();

    -- Reject if already at or over capacity
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

-- ── 4. delete_expired_slot_locks ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION delete_expired_slot_locks()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM slot_locks WHERE expires_at < NOW();
END;
$$;

-- pg_cron: clean up expired locks every minute (guarded — no-op if unavailable)
DO $outer$
BEGIN
  PERFORM cron.schedule(
    'cleanup-slot-locks',
    '* * * * *',
    $cron$SELECT delete_expired_slot_locks()$cron$
  );
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$outer$;

-- ── 5. Rejection trigger ──────────────────────────────────────────────────────

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
  -- Only fire when status transitions TO 'rejected'
  IF NEW.status <> 'rejected' OR OLD.status = 'rejected' THEN
    RETURN NEW;
  END IF;

  -- Skip if no vendor, date, or slot (can't lock without all three)
  IF NEW.vendor_id IS NULL OR NEW.service_date IS NULL OR NEW.scheduled_time IS NULL THEN
    RETURN NEW;
  END IF;

  -- InstaHelp booking?
  SELECT mode_id, duration_id
  INTO   v_mode_id, v_duration_id
  FROM   instahelp_bookings
  WHERE  booking_id = NEW.id;

  IF FOUND THEN
    PERFORM lock_slot(
      NEW.vendor_id,
      NEW.service_date::DATE,
      NEW.scheduled_time,
      'rejection',
      v_mode_id,
      v_duration_id,
      NULL,
      NULL,
      NEW.id
    );
    RETURN NEW;
  END IF;

  -- Catalog vendor (VCS) booking?
  IF NEW.booking_source = 'catalog_vendor' THEN
    SELECT service_id
    INTO   v_service_id
    FROM   booking_items
    WHERE  booking_id = NEW.id
      AND  service_id IS NOT NULL
    LIMIT 1;

    IF FOUND AND v_service_id IS NOT NULL THEN
      PERFORM lock_slot(
        NEW.vendor_id,
        NEW.service_date::DATE,
        NEW.scheduled_time,
        'rejection',
        NULL,
        NULL,
        v_service_id,
        NULL,
        NEW.id
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_booking_rejection_slot_lock ON bookings;
CREATE TRIGGER trg_booking_rejection_slot_lock
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_booking_rejection_slot_lock();

-- ── 6. Updated get_instahelp_slots ───────────────────────────────────────────
--
-- Extends the existing RPC to also count active slot_locks so that:
--   is_available = (bookings_count + checkout_lock_count < max AND no rejection_lock)
-- This handles any max_bookings_per_slot value correctly.

CREATE OR REPLACE FUNCTION get_instahelp_slots(
  p_mode_id     UUID,
  p_duration_id UUID,
  p_date        DATE
)
RETURNS TABLE(
  slot_time      TEXT,
  is_available   BOOLEAN,
  bookings_count INTEGER,
  max_bookings   INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_config     RECORD;
  v_duration   RECORD;
  v_override   RECORD;
  v_has_config BOOLEAN := FALSE;
  v_start      TIME;
  v_end        TIME;
  v_interval   INTEGER;
  v_max        INTEGER;
  v_cur        TIME;
  v_dow        INTEGER;
  v_slot_str   TEXT;
  v_count      INTEGER;
  v_lock_count INTEGER;
  v_reject_count INTEGER;
BEGIN
  -- Duration config is required
  SELECT slot_start_time, slot_end_time, slot_interval_minutes, max_bookings_per_slot
  INTO   v_duration
  FROM   instahelp_durations
  WHERE  id = p_duration_id AND is_active = TRUE;

  IF NOT FOUND THEN RETURN; END IF;

  -- Global config is optional — only used for working_days
  SELECT * INTO v_config
  FROM   instahelp_slot_config
  WHERE  mode_id = p_mode_id AND is_active = TRUE;
  v_has_config := FOUND;

  -- Date override (range-based): most specific range wins
  SELECT * INTO v_override
  FROM   instahelp_date_overrides
  WHERE  mode_id = p_mode_id
    AND  p_date BETWEEN start_date AND end_date
  ORDER  BY start_date DESC
  LIMIT  1;

  IF FOUND THEN
    IF NOT v_override.is_available THEN RETURN; END IF;
    v_start := COALESCE(v_override.custom_start_time, v_duration.slot_start_time);
    v_end   := COALESCE(v_override.custom_end_time,   v_duration.slot_end_time);
  ELSE
    -- Check working days only if global config exists
    IF v_has_config THEN
      v_dow := EXTRACT(DOW FROM p_date)::INTEGER;
      IF NOT (v_config.working_days @> to_jsonb(v_dow)) THEN RETURN; END IF;
    END IF;
    v_start := v_duration.slot_start_time;
    v_end   := v_duration.slot_end_time;
  END IF;

  v_interval := v_duration.slot_interval_minutes;
  v_max      := v_duration.max_bookings_per_slot;

  v_cur := v_start;
  WHILE v_cur < v_end LOOP
    v_slot_str := TO_CHAR((p_date + v_cur)::TIMESTAMP, 'FMHH12:MI AM');

    -- Existing confirmed bookings
    SELECT COUNT(*)
    INTO   v_count
    FROM   bookings b
    JOIN   instahelp_bookings ib ON ib.booking_id = b.id
    WHERE  ib.mode_id       = p_mode_id
      AND  ib.duration_id   = p_duration_id
      AND  b.service_date   = p_date
      AND  b.scheduled_time = v_slot_str
      AND  b.status NOT IN ('cancelled', 'rejected');

    -- Active checkout locks (in-flight bookings consuming capacity)
    SELECT COUNT(*)
    INTO   v_lock_count
    FROM   slot_locks sl
    WHERE  sl.mode_id      = p_mode_id
      AND  sl.duration_id  = p_duration_id
      AND  sl.service_date = p_date
      AND  sl.slot_time    = v_slot_str
      AND  sl.lock_type    = 'checkout'
      AND  sl.expires_at   > NOW();

    -- Active rejection lock (cooldown after vendor rejection)
    SELECT COUNT(*)
    INTO   v_reject_count
    FROM   slot_locks sl
    WHERE  sl.mode_id      = p_mode_id
      AND  sl.service_date = p_date
      AND  sl.slot_time    = v_slot_str
      AND  sl.lock_type    = 'rejection'
      AND  sl.expires_at   > NOW();

    RETURN QUERY SELECT
      v_slot_str,
      (v_count + v_lock_count < v_max AND v_reject_count = 0),
      v_count::INTEGER,
      v_max;

    v_cur := v_cur + (v_interval || ' minutes')::INTERVAL;
  END LOOP;
END;
$$;
