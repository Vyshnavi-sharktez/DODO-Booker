-- ============================================================
-- Availability Blocks — temporary slot-pause overlay
-- ============================================================
-- Creates the availability_blocks table and supporting RPC so
-- specific dates/date-ranges can be paused for global, category,
-- service, or vendor scope without touching existing schedules.
--
-- Scopes:
--   global   — blocks every service for the period
--   category — blocks all services that are descendants of the node
--   service  — blocks a single leaf service node
--   vendor   — blocks all bookings for the vendor
--
-- A NULL blocked_slots means a full-day block.
-- A non-null blocked_slots array means only those slot labels are blocked.
-- ============================================================

-- ── Table ────────────────────────────────────────────────────────────────────

CREATE TABLE availability_blocks (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  scope         TEXT         NOT NULL CHECK (scope IN ('global', 'category', 'service', 'vendor')),
  node_id       UUID         REFERENCES catalog_nodes(id) ON DELETE CASCADE,
  vendor_id     UUID         REFERENCES vendors(id) ON DELETE CASCADE,
  start_date    DATE         NOT NULL,
  end_date      DATE         NOT NULL,
  blocked_slots TEXT[],        -- NULL = full-day; array = partial-day
  reason        TEXT,
  is_enabled    BOOLEAN      NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

  CONSTRAINT chk_ab_scope_fk CHECK (
    (scope = 'global'   AND node_id IS NULL     AND vendor_id IS NULL) OR
    (scope = 'category' AND node_id IS NOT NULL  AND vendor_id IS NULL) OR
    (scope = 'service'  AND node_id IS NOT NULL  AND vendor_id IS NULL) OR
    (scope = 'vendor'   AND vendor_id IS NOT NULL AND node_id IS NULL)
  ),
  CONSTRAINT chk_ab_dates CHECK (end_date >= start_date)
);

CREATE INDEX idx_ab_scope
  ON availability_blocks(scope)
  WHERE is_enabled = true;

CREATE INDEX idx_ab_node
  ON availability_blocks(node_id)
  WHERE node_id IS NOT NULL AND is_enabled = true;

CREATE INDEX idx_ab_vendor
  ON availability_blocks(vendor_id)
  WHERE vendor_id IS NOT NULL AND is_enabled = true;

CREATE INDEX idx_ab_dates
  ON availability_blocks(start_date, end_date);

-- ── RLS ──────────────────────────────────────────────────────────────────────

ALTER TABLE availability_blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ab_anon_read"
  ON availability_blocks FOR SELECT TO anon
  USING (true);

CREATE POLICY "ab_auth_all"
  ON availability_blocks FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);

-- ── check_availability_block RPC ─────────────────────────────────────────────
-- Returns one row describing the combined block state for (service, vendor, date).
--
-- is_full_day_blocked  — true when any matching block is a full-day block
-- blocked_slots        — union of all partial-day blocked slot labels
--                        (empty array when no partial blocks, NULL when full-day)
-- block_reason         — reason from the first matching block found
--
-- Callable by anon (customer app) and authenticated (admin / triggers).

CREATE OR REPLACE FUNCTION check_availability_block(
  p_service_id UUID,
  p_vendor_id  UUID,
  p_date       DATE
)
RETURNS TABLE(
  is_full_day_blocked  BOOLEAN,
  blocked_slots        TEXT[],
  block_reason         TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE
  -- Recursively walk up from the service node to collect all ancestor ids.
  ancestors(node_id) AS (
    SELECT r.parent_id
    FROM   catalog_node_relationships r
    WHERE  r.child_id = p_service_id
    UNION
    SELECT r.parent_id
    FROM   catalog_node_relationships r
    INNER JOIN ancestors a ON r.child_id = a.node_id
  ),

  -- All active blocks that cover this (service, vendor, date) combination.
  matched AS (
    SELECT ab.blocked_slots, ab.reason, ab.scope
    FROM   availability_blocks ab
    WHERE  ab.is_enabled = true
      AND  p_date BETWEEN ab.start_date AND ab.end_date
      AND  (
             -- 1. global
             ab.scope = 'global'
             -- 2. vendor
             OR (ab.scope = 'vendor' AND p_vendor_id IS NOT NULL
                 AND ab.vendor_id = p_vendor_id)
             -- 3. service (direct match)
             OR (ab.scope = 'service' AND p_service_id IS NOT NULL
                 AND ab.node_id = p_service_id)
             -- 4. category (service is a descendant)
             OR (ab.scope = 'category' AND p_service_id IS NOT NULL
                 AND ab.node_id IN (SELECT a.node_id FROM ancestors a))
           )
  ),

  -- Aggregate: is any block full-day?  Collect partial-day slot union.
  agg AS (
    SELECT
      bool_or(m.blocked_slots IS NULL)                          AS has_full_day,
      array_agg(DISTINCT s ORDER BY s)
        FILTER (WHERE m.blocked_slots IS NOT NULL)              AS partial_slots,
      min(m.reason)                                             AS first_reason
    FROM matched m
    LEFT JOIN LATERAL unnest(m.blocked_slots) s ON true
  )

  SELECT
    agg.has_full_day,
    CASE WHEN agg.has_full_day THEN NULL::TEXT[]
         ELSE COALESCE(agg.partial_slots, '{}')
    END,
    agg.first_reason
  FROM agg;
END;
$$;

GRANT EXECUTE ON FUNCTION check_availability_block(UUID, UUID, DATE) TO anon;
GRANT EXECUTE ON FUNCTION check_availability_block(UUID, UUID, DATE) TO authenticated;

-- ── Booking validation trigger ─────────────────────────────────────────────────
-- Runs BEFORE INSERT so a booking cannot be created during a block even if the
-- UI was stale (race condition / replay attack).

CREATE OR REPLACE FUNCTION fn_validate_booking_not_blocked()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_date         DATE;
  v_is_full_day  BOOLEAN;
  v_slots        TEXT[];
BEGIN
  IF NEW.service_date IS NULL OR NEW.service_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_date := NEW.service_date::DATE;

  SELECT r.is_full_day_blocked, r.blocked_slots
  INTO   v_is_full_day, v_slots
  FROM   check_availability_block(
           NEW.service_id::UUID,
           NEW.preferred_vendor_id::UUID,
           v_date
         ) r;

  IF v_is_full_day IS TRUE THEN
    RAISE EXCEPTION
      'Availability block: % is currently unavailable for bookings.',
      v_date;
  END IF;

  IF NEW.scheduled_time IS NOT NULL
     AND array_length(v_slots, 1) > 0
     AND NEW.scheduled_time = ANY(v_slots)
  THEN
    RAISE EXCEPTION
      'Availability block: the % slot on % is currently unavailable.',
      NEW.scheduled_time, v_date;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_booking_not_blocked ON bookings;

CREATE TRIGGER trg_validate_booking_not_blocked
  BEFORE INSERT ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_validate_booking_not_blocked();
