-- Migration: 20261118000016_booking_slot_capacity_trigger.sql
--
-- Root cause of concurrent double-booking:
--
--   lock_slot() uses pg_advisory_xact_lock to serialise concurrent LOCK
--   ACQUISITIONS, but that advisory lock is held only for the duration of the
--   lock_slot transaction (a separate HTTP round-trip that completes before
--   createBooking is called).
--
--   The subsequent bookings.insert runs in a completely new transaction with
--   no mutual exclusion.  Two clients that both obtained checkout locks (or
--   whose locks expired) can reach the INSERT simultaneously.  The INSERT has
--   no server-side capacity check, so both succeed.
--
-- Fix: BEFORE INSERT trigger fn_enforce_booking_slot_capacity that:
--   1. Acquires pg_advisory_xact_lock with the SAME key as lock_slot uses for
--      regular-service calls, so the trigger and lock_slot contend on the
--      same lock and serialise against each other.
--   2. Resolves max capacity using the same 3-level hierarchy as lock_slot
--      (catalog_node_configs → service_scheduling → global_scheduling → 5).
--   3. Counts confirmed bookings already in the slot (excluding
--      cancelled/rejected rows — the INSERT being checked is not yet visible).
--   4. RAISES EXCEPTION 'slot_taken' if at capacity.
--
-- Scope: only regular DODO-catalog service bookings.
--   • service_id IS NULL        → InstaHelp / VCS (have their own guards)
--   • scheduled_time IS NULL    → unscheduled AMC placeholder rows
--   • service_date IS NULL      → same
--   • status != 'pending'       → warranty reworks, admin-forced statuses
--   • booking_source = 'catalog_vendor' → VCS (vendor-scoped lock already applies)
--
-- The trigger fires before every INSERT on bookings.  Supabase table inserts
-- from the customer app, booking_gate, and checkout all hit this path.

CREATE OR REPLACE FUNCTION fn_enforce_booking_slot_capacity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_max        INT;
  v_booked     INT;
  v_node_max   INT;
  v_svc_max    INT;
  v_svc_found  BOOLEAN := FALSE;
  v_global_max INT;
BEGIN
  -- ── Scope guard ───────────────────────────────────────────────────────────
  -- Skip rows that do not represent a schedulable regular-service booking.
  IF NEW.service_id    IS NULL THEN RETURN NEW; END IF;
  IF NEW.scheduled_time IS NULL THEN RETURN NEW; END IF;
  IF NEW.service_date  IS NULL THEN RETURN NEW; END IF;
  IF NEW.status != 'pending'   THEN RETURN NEW; END IF;  -- warranty_pending_approval etc.
  IF COALESCE(NEW.booking_source, '') = 'catalog_vendor' THEN RETURN NEW; END IF;

  -- ── Advisory lock ─────────────────────────────────────────────────────────
  -- Key matches lock_slot's regular-service key exactly:
  --   hashtext('nil|<date>|<slot_time>|||<service_id>')
  -- This ensures the trigger and lock_slot contend on the same lock,
  -- serialising a concurrent lock_slot + INSERT pair for the same slot.
  PERFORM pg_advisory_xact_lock(
    hashtext(
      'nil'
      || '|' || NEW.service_date::text
      || '|' || NEW.scheduled_time
      || '|||'
      || NEW.service_id::text
    )
  );

  -- ── Resolve max capacity (mirror of lock_slot priority chain) ─────────────

  -- Priority 1: catalog_node_configs — walk from product up to root.
  SELECT (cnc.config->>'max_bookings_per_slot')::INT INTO v_node_max
  FROM (
    WITH RECURSIVE node_walk(id, depth) AS (
      SELECT NEW.service_id, 0
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
    -- use_global_schedule controls slot structure only — capacity always wins.
    SELECT max_bookings_per_slot INTO v_svc_max
    FROM   service_scheduling
    WHERE  service_id = NEW.service_id;
    v_svc_found := FOUND;

    -- Priority 3: global_scheduling fallback.
    SELECT max_bookings_per_slot INTO v_global_max
    FROM   global_scheduling LIMIT 1;

    IF v_svc_found AND v_svc_max IS NOT NULL AND v_svc_max > 0 THEN
      v_max := v_svc_max;
    ELSE
      v_max := COALESCE(v_global_max, 5);
    END IF;
  END IF;

  -- ── Count confirmed bookings already occupying this slot ──────────────────
  -- The INSERT being validated is not yet visible (BEFORE trigger), so this
  -- count represents other customers' committed bookings.
  SELECT COUNT(*) INTO v_booked
  FROM   bookings
  WHERE  service_id         = NEW.service_id
    AND  service_date::DATE = NEW.service_date::DATE
    AND  scheduled_time     = NEW.scheduled_time
    AND  status NOT IN ('cancelled', 'rejected');

  IF v_booked >= v_max THEN
    RAISE EXCEPTION 'slot_taken'
      USING HINT    = 'This slot has just been taken. Please select another time slot.',
            ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_booking_slot_capacity ON bookings;
CREATE TRIGGER trg_enforce_booking_slot_capacity
  BEFORE INSERT ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_enforce_booking_slot_capacity();
