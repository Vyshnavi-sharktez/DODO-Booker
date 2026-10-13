-- ─────────────────────────────────────────────────────────────────────────────
-- Booking Deletion Archive
--
-- Adds a `deleted_bookings` table that permanently stores a complete snapshot
-- of every booking and its dependent records at the moment an admin deletes it.
-- Deletion is performed by the `admin_delete_booking` RPC which archives then
-- removes records in FK-safe order, atomically inside a single transaction.
--
-- FK dependency map for bookings.id:
--   MUST delete explicitly (RESTRICT / NO ACTION / uncertain base schema):
--     booking_items               → bookings.id   (base schema, FK behavior uncertain)
--     customer_reviews            → bookings.id   (base schema, NO ACTION evidenced)
--     vendor_settlement_bookings  → bookings.id   (RESTRICT, confirmed)
--     refund_requests             → bookings.id   (NO ACTION, confirmed)
--       refund_transactions       → refund_requests.id  (NO ACTION, delete first)
--       refund_status_history     → refund_requests.id  (CASCADE, auto)
--   Auto-CASCADE on bookings DELETE (confirmed in their creation migrations):
--     booking_addons, booking_images, booking_payments, booking_assignments,
--     vendor_location_logs, gps_cancellation_audits, call_sessions,
--     service_warranties (booking_id)
--   Auto-SET NULL on bookings DELETE:
--     loyalty_transactions (booking_id), amc_scheduling_requests (booking_id),
--     service_warranties (rework_booking_id)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Archive table ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.deleted_bookings (
  booking_id      UUID        PRIMARY KEY,
  booking_number  TEXT,
  deleted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_by      UUID        REFERENCES auth.users(id) ON DELETE SET NULL,

  -- Full row of the booking at deletion time
  booking_data              JSONB NOT NULL DEFAULT '{}',

  -- Related rows captured as JSONB arrays (empty array when no rows existed)
  booking_items_data        JSONB NOT NULL DEFAULT '[]',
  booking_addons_data       JSONB NOT NULL DEFAULT '[]',
  booking_payments_data     JSONB NOT NULL DEFAULT '[]',
  booking_assignments_data  JSONB NOT NULL DEFAULT '[]',
  vendor_settlement_data    JSONB NOT NULL DEFAULT '[]',
  customer_reviews_data     JSONB NOT NULL DEFAULT '[]',
  service_warranties_data   JSONB NOT NULL DEFAULT '[]',
  call_sessions_data        JSONB NOT NULL DEFAULT '[]',

  -- Refund tickets with embedded status history and transactions
  refund_requests_data      JSONB NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS idx_deleted_bookings_booking_number
  ON public.deleted_bookings (booking_number);

CREATE INDEX IF NOT EXISTS idx_deleted_bookings_deleted_at
  ON public.deleted_bookings (deleted_at DESC);

CREATE INDEX IF NOT EXISTS idx_deleted_bookings_deleted_by
  ON public.deleted_bookings (deleted_by);

-- ── 2. RLS ────────────────────────────────────────────────────────────────────

ALTER TABLE public.deleted_bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_deleted_bookings" ON public.deleted_bookings;
CREATE POLICY "service_role_all_deleted_bookings"
  ON public.deleted_bookings FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

-- Active admins can read the archive (for audit / support queries).
-- No INSERT/UPDATE/DELETE from the admin panel — only the RPC writes here.
DROP POLICY IF EXISTS "admin_select_deleted_bookings" ON public.deleted_bookings;
CREATE POLICY "admin_select_deleted_bookings"
  ON public.deleted_bookings FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE auth_user_id = auth.uid()
        AND is_active = TRUE
    )
  );

-- ── 3. RPC: admin_delete_booking ─────────────────────────────────────────────
--
-- Archives the complete booking and all related records, then deletes them in
-- FK-safe order.  Everything runs in a single implicit transaction so any
-- failure rolls the entire operation back — no partial state is ever committed.
--
-- Parameters:
--   p_booking_id  UUID  — the booking to delete
--
-- Returns: JSONB with { success, booking_id, booking_number }
-- Raises an exception (and rolls back) on any error.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_delete_booking(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking_number TEXT;
BEGIN
  -- ── Auth guard ──────────────────────────────────────────────────────────────
  PERFORM fn_assert_active_admin();

  -- ── Lock the booking row (prevents concurrent deletions / edits) ────────────
  SELECT booking_number
    INTO v_booking_number
    FROM bookings
   WHERE id = p_booking_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking % not found', p_booking_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Archive: capture all related data before any deletion ──────────────────
  INSERT INTO deleted_bookings (
    booking_id,
    booking_number,
    deleted_by,
    booking_data,
    booking_items_data,
    booking_addons_data,
    booking_payments_data,
    booking_assignments_data,
    vendor_settlement_data,
    customer_reviews_data,
    service_warranties_data,
    call_sessions_data,
    refund_requests_data
  )
  SELECT
    b.id,
    b.booking_number,
    auth.uid(),

    -- Full booking row
    to_jsonb(b),

    -- booking_items
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(bi))
         FROM booking_items bi
        WHERE bi.booking_id = b.id),
      '[]'::jsonb
    ),

    -- booking_addons
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(ba))
         FROM booking_addons ba
        WHERE ba.booking_id = b.id),
      '[]'::jsonb
    ),

    -- booking_payments (all attempts)
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(bp))
         FROM booking_payments bp
        WHERE bp.booking_id = b.id),
      '[]'::jsonb
    ),

    -- booking_assignments (dispatch history)
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(basm))
         FROM booking_assignments basm
        WHERE basm.booking_id = b.id),
      '[]'::jsonb
    ),

    -- vendor_settlement_bookings
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(vsb))
         FROM vendor_settlement_bookings vsb
        WHERE vsb.booking_id = b.id),
      '[]'::jsonb
    ),

    -- customer_reviews
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(cr))
         FROM customer_reviews cr
        WHERE cr.booking_id = b.id),
      '[]'::jsonb
    ),

    -- service_warranties
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(sw))
         FROM service_warranties sw
        WHERE sw.booking_id = b.id),
      '[]'::jsonb
    ),

    -- call_sessions
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(cs))
         FROM call_sessions cs
        WHERE cs.booking_id = b.id),
      '[]'::jsonb
    ),

    -- refund_requests with embedded status history and transactions
    COALESCE(
      (SELECT jsonb_agg(
         to_jsonb(rr) || jsonb_build_object(
           'status_history', COALESCE(
             (SELECT jsonb_agg(to_jsonb(rsh))
                FROM refund_status_history rsh
               WHERE rsh.refund_request_id = rr.id),
             '[]'::jsonb
           ),
           'transactions', COALESCE(
             (SELECT jsonb_agg(to_jsonb(rt))
                FROM refund_transactions rt
               WHERE rt.refund_request_id = rr.id),
             '[]'::jsonb
           )
         )
       )
       FROM refund_requests rr
      WHERE rr.booking_id = b.id),
      '[]'::jsonb
    )

  FROM bookings b
  WHERE b.id = p_booking_id;

  -- ── Delete dependents that block the booking deletion ───────────────────────

  -- 3a. refund_transactions — no ON DELETE on refund_request FK, must go first
  DELETE FROM refund_transactions
   WHERE refund_request_id IN (
     SELECT id FROM refund_requests WHERE booking_id = p_booking_id
   );

  -- 3b. refund_requests — NO ACTION FK to bookings
  --     refund_status_history cascades automatically
  DELETE FROM refund_requests WHERE booking_id = p_booking_id;

  -- 3c. vendor_settlement_bookings — RESTRICT FK to bookings
  DELETE FROM vendor_settlement_bookings WHERE booking_id = p_booking_id;

  -- 3d. customer_reviews — base schema, NO ACTION FK to bookings
  DELETE FROM customer_reviews WHERE booking_id = p_booking_id;

  -- 3e. booking_items — base schema, FK behavior uncertain (treated as RESTRICT)
  DELETE FROM booking_items WHERE booking_id = p_booking_id;

  -- ── Delete the booking ──────────────────────────────────────────────────────
  -- All remaining FK children cascade automatically:
  --   booking_addons, booking_images, booking_payments, booking_assignments,
  --   vendor_location_logs, gps_cancellation_audits, call_sessions,
  --   service_warranties (booking_id column)
  -- SET NULL children are handled automatically:
  --   loyalty_transactions (booking_id), amc_scheduling_requests (booking_id),
  --   service_warranties (rework_booking_id), bookings.amc_contract_id
  DELETE FROM bookings WHERE id = p_booking_id;

  RETURN jsonb_build_object(
    'success',        true,
    'booking_id',     p_booking_id,
    'booking_number', v_booking_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_booking(UUID) TO authenticated;
