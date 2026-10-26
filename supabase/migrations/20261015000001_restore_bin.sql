-- ─────────────────────────────────────────────────────────────────────────────
-- Restore Bin
--
-- Adds three RPCs that power the admin Restore Bin page:
--
--   admin_fetch_deleted_bookings()
--     Returns every row from deleted_bookings joined with customer name/phone
--     and the deleting admin's name.  Used by the Flutter page to populate
--     the table without N+1 queries.
--
--   admin_restore_booking(p_booking_id UUID)
--     Atomically re-inserts a booking (and all related rows) from its JSONB
--     snapshot back into the live tables, then removes it from the archive.
--     Non-critical relations (payments, assignments, reviews …) are wrapped in
--     savepoint sub-blocks so a partial failure only skips that relation.
--
--   admin_purge_expired_bookings()
--     Deletes archive rows whose deleted_at is older than the configured
--     retention period.  Reads 'deleted_bookings_retention_value' and
--     'deleted_bookings_retention_unit' from the settings table.
--
-- Retention defaults and a pg_cron daily job are also created here.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. List deleted bookings (with customer and admin info) ──────────────────

DROP FUNCTION IF EXISTS public.admin_fetch_deleted_bookings();

CREATE OR REPLACE FUNCTION public.admin_fetch_deleted_bookings()
RETURNS TABLE (
  booking_id        UUID,
  booking_number    TEXT,
  deleted_at        TIMESTAMPTZ,
  deleted_by        UUID,
  deleted_by_name   TEXT,
  customer_id       UUID,
  customer_name     TEXT,
  customer_phone    TEXT,
  status            TEXT,
  total_amount      NUMERIC,
  service_date      DATE,
  address           TEXT,
  service_names     TEXT[],
  items_count       INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_assert_active_admin();

  RETURN QUERY
  SELECT
    db.booking_id,
    db.booking_number,
    db.deleted_at,
    db.deleted_by,
    au.full_name                                                    AS deleted_by_name,
    (db.booking_data->>'customer_id')::uuid                        AS customer_id,
    c.full_name                                                     AS customer_name,
    c.phone                                                         AS customer_phone,
    db.booking_data->>'status'                                      AS status,
    (db.booking_data->>'total_amount')::numeric                     AS total_amount,
    (db.booking_data->>'service_date')::date                        AS service_date,
    db.booking_data->>'address'                                     AS address,
    ARRAY(
      SELECT COALESCE(bi->>'service_name', bi->>'item_name', '')
      FROM   jsonb_array_elements(db.booking_items_data) AS bi
      WHERE  COALESCE(bi->>'service_name', bi->>'item_name', '') <> ''
    )                                                               AS service_names,
    jsonb_array_length(db.booking_items_data)                       AS items_count
  FROM deleted_bookings db
  LEFT JOIN customers   c  ON c.id            = (db.booking_data->>'customer_id')::uuid
  LEFT JOIN admin_users au ON au.auth_user_id = db.deleted_by
  ORDER BY db.deleted_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_fetch_deleted_bookings() TO authenticated;


-- ── 2. Restore a booking from the archive ────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_restore_booking(UUID);

CREATE OR REPLACE FUNCTION public.admin_restore_booking(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_archived       deleted_bookings%ROWTYPE;
  v_booking_number TEXT;
  v_rr             RECORD;
BEGIN
  PERFORM fn_assert_active_admin();

  -- Lock archive row to prevent concurrent restores
  SELECT * INTO v_archived
    FROM deleted_bookings
   WHERE booking_id = p_booking_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deleted booking % not found in archive', p_booking_id
      USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (SELECT 1 FROM bookings WHERE id = p_booking_id) THEN
    RAISE EXCEPTION 'Booking % already exists in active bookings', p_booking_id
      USING ERRCODE = 'P0001';
  END IF;

  v_booking_number := v_archived.booking_number;

  -- ── Core booking row (critical — any failure rolls back the whole function) ──
  INSERT INTO bookings
  SELECT * FROM jsonb_populate_record(null::bookings, v_archived.booking_data);

  -- Ensure booking_number was not overwritten by an auto-generation trigger
  UPDATE bookings
     SET booking_number = v_booking_number
   WHERE id = p_booking_id
     AND booking_number IS DISTINCT FROM v_booking_number;

  -- ── booking_items: try exact restore; on FK violation (catalog node deleted)  ─
  -- ──  retry with service_id nullified for the missing nodes.                   ─
  BEGIN
    IF jsonb_array_length(v_archived.booking_items_data) > 0 THEN
      INSERT INTO booking_items
      SELECT * FROM jsonb_populate_recordset(null::booking_items, v_archived.booking_items_data);
    END IF;
  EXCEPTION
    WHEN foreign_key_violation THEN
      RAISE WARNING 'booking_items: catalog FK violation for %, retrying with service_id nullified', p_booking_id;
      BEGIN
        IF jsonb_array_length(v_archived.booking_items_data) > 0 THEN
          INSERT INTO booking_items
          SELECT * FROM jsonb_populate_recordset(
            null::booking_items,
            (
              SELECT jsonb_agg(
                CASE
                  WHEN (bi->>'service_id') IS NULL THEN bi
                  WHEN NOT EXISTS (
                    SELECT 1 FROM catalog_nodes WHERE id = (bi->>'service_id')::uuid
                  ) THEN bi - 'service_id'
                  ELSE bi
                END
              )
              FROM jsonb_array_elements(v_archived.booking_items_data) AS bi
            )
          );
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'booking_items restore fallback failed for %: %', p_booking_id, SQLERRM;
      END;
    WHEN OTHERS THEN
      RAISE WARNING 'booking_items restore failed for %: %', p_booking_id, SQLERRM;
  END;

  -- ── Non-critical relations (each wrapped in a savepoint sub-block) ────────────

  BEGIN
    IF jsonb_array_length(v_archived.booking_addons_data) > 0 THEN
      INSERT INTO booking_addons
      SELECT * FROM jsonb_populate_recordset(null::booking_addons, v_archived.booking_addons_data);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'booking_addons restore skipped for %: %', p_booking_id, SQLERRM;
  END;

  BEGIN
    IF jsonb_array_length(v_archived.booking_payments_data) > 0 THEN
      INSERT INTO booking_payments
      SELECT * FROM jsonb_populate_recordset(null::booking_payments, v_archived.booking_payments_data);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'booking_payments restore skipped for %: %', p_booking_id, SQLERRM;
  END;

  BEGIN
    IF jsonb_array_length(v_archived.booking_assignments_data) > 0 THEN
      INSERT INTO booking_assignments
      SELECT * FROM jsonb_populate_recordset(null::booking_assignments, v_archived.booking_assignments_data);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'booking_assignments restore skipped for %: %', p_booking_id, SQLERRM;
  END;

  BEGIN
    IF jsonb_array_length(v_archived.call_sessions_data) > 0 THEN
      INSERT INTO call_sessions
      SELECT * FROM jsonb_populate_recordset(null::call_sessions, v_archived.call_sessions_data);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'call_sessions restore skipped for %: %', p_booking_id, SQLERRM;
  END;

  BEGIN
    IF jsonb_array_length(v_archived.customer_reviews_data) > 0 THEN
      INSERT INTO customer_reviews
      SELECT * FROM jsonb_populate_recordset(null::customer_reviews, v_archived.customer_reviews_data);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'customer_reviews restore skipped for %: %', p_booking_id, SQLERRM;
  END;

  BEGIN
    IF jsonb_array_length(v_archived.service_warranties_data) > 0 THEN
      INSERT INTO service_warranties
      SELECT * FROM jsonb_populate_recordset(null::service_warranties, v_archived.service_warranties_data);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'service_warranties restore skipped for %: %', p_booking_id, SQLERRM;
  END;

  BEGIN
    IF jsonb_array_length(v_archived.vendor_settlement_data) > 0 THEN
      INSERT INTO vendor_settlement_bookings
      SELECT * FROM jsonb_populate_recordset(null::vendor_settlement_bookings, v_archived.vendor_settlement_data);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'vendor_settlement_bookings restore skipped for %: %', p_booking_id, SQLERRM;
  END;

  -- Refund requests (status_history and transactions are embedded in the snapshot)
  FOR v_rr IN
    SELECT t.value AS rr_json
    FROM   jsonb_array_elements(v_archived.refund_requests_data) AS t(value)
  LOOP
    BEGIN
      INSERT INTO refund_requests
      SELECT * FROM jsonb_populate_record(
        null::refund_requests,
        v_rr.rr_json - 'status_history' - 'transactions'
      );
      BEGIN
        IF jsonb_array_length(v_rr.rr_json->'status_history') > 0 THEN
          INSERT INTO refund_status_history
          SELECT * FROM jsonb_populate_recordset(
            null::refund_status_history, v_rr.rr_json->'status_history'
          );
        END IF;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      BEGIN
        IF jsonb_array_length(v_rr.rr_json->'transactions') > 0 THEN
          INSERT INTO refund_transactions
          SELECT * FROM jsonb_populate_recordset(
            null::refund_transactions, v_rr.rr_json->'transactions'
          );
        END IF;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'refund_request restore skipped for %: %', p_booking_id, SQLERRM;
    END;
  END LOOP;

  -- Remove from restore bin
  DELETE FROM deleted_bookings WHERE booking_id = p_booking_id;

  RETURN jsonb_build_object(
    'success',        true,
    'booking_id',     p_booking_id,
    'booking_number', v_booking_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_restore_booking(UUID) TO authenticated;


-- ── 3. Purge expired deleted bookings ────────────────────────────────────────
--
-- Reads 'deleted_bookings_retention_value' (integer) and
-- 'deleted_bookings_retention_unit' ('days' | 'weeks' | 'months') from the
-- settings table.  PostgreSQL interval arithmetic handles calendar months
-- correctly (e.g. '1 months'::interval from 2026-01-31 → 2026-02-28).

DROP FUNCTION IF EXISTS public.admin_purge_expired_bookings();

CREATE OR REPLACE FUNCTION public.admin_purge_expired_bookings()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_value   INTEGER;
  v_unit    TEXT;
  v_cutoff  TIMESTAMPTZ;
  v_purged  INTEGER;
BEGIN
  PERFORM fn_assert_active_admin();

  SELECT (s.setting_value)::integer
    INTO v_value
    FROM settings s
   WHERE s.setting_key = 'deleted_bookings_retention_value'
   LIMIT 1;

  IF v_value IS NULL OR v_value < 1 THEN v_value := 30; END IF;

  SELECT s.setting_value
    INTO v_unit
    FROM settings s
   WHERE s.setting_key = 'deleted_bookings_retention_unit'
   LIMIT 1;

  IF v_unit IS NULL OR v_unit NOT IN ('days', 'weeks', 'months') THEN
    v_unit := 'days';
  END IF;

  v_cutoff := now() - (v_value::text || ' ' || v_unit)::interval;

  DELETE FROM deleted_bookings
   WHERE deleted_at <= v_cutoff;

  GET DIAGNOSTICS v_purged = ROW_COUNT;

  RETURN jsonb_build_object(
    'success',          true,
    'purged_count',     v_purged,
    'retention_value',  v_value,
    'retention_unit',   v_unit,
    'cutoff_timestamp', v_cutoff
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_purge_expired_bookings() TO authenticated;


-- Internal version for pg_cron (no auth.uid() context available in cron jobs)
CREATE OR REPLACE FUNCTION public._purge_expired_bookings_cron()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_value   INTEGER;
  v_unit    TEXT;
  v_cutoff  TIMESTAMPTZ;
  v_purged  INTEGER;
BEGIN
  SELECT (s.setting_value)::integer
    INTO v_value
    FROM settings s
   WHERE s.setting_key = 'deleted_bookings_retention_value'
   LIMIT 1;

  IF v_value IS NULL OR v_value < 1 THEN v_value := 30; END IF;

  SELECT s.setting_value
    INTO v_unit
    FROM settings s
   WHERE s.setting_key = 'deleted_bookings_retention_unit'
   LIMIT 1;

  IF v_unit IS NULL OR v_unit NOT IN ('days', 'weeks', 'months') THEN
    v_unit := 'days';
  END IF;

  v_cutoff := now() - (v_value::text || ' ' || v_unit)::interval;

  DELETE FROM deleted_bookings WHERE deleted_at <= v_cutoff;
  GET DIAGNOSTICS v_purged = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true, 'purged_count', v_purged,
    'cutoff_timestamp', v_cutoff
  );
END;
$$;
-- Not granted to authenticated — only callable by superuser/pg_cron


-- ── 4. Default retention settings ────────────────────────────────────────────

INSERT INTO settings (setting_key, setting_value)
VALUES
  ('deleted_bookings_retention_value', '30'),
  ('deleted_bookings_retention_unit',  'days')
ON CONFLICT (setting_key) DO NOTHING;


-- ── 5. pg_cron: daily purge at 02:00 UTC ─────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('purge-deleted-bookings-daily');
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'purge-deleted-bookings-daily',
      '0 2 * * *',
      $cron$ SELECT public._purge_expired_bookings_cron(); $cron$
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pg_cron schedule failed (extension may not be enabled): %', SQLERRM;
END;
$$;
