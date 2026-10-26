-- ─────────────────────────────────────────────────────────────────────────────
-- Fix booking deletion: handle booking_images FK constraint
--
-- Root cause: booking_images has a named FK constraint fk_booking_images_booking
-- that does NOT cascade on DELETE.  admin_delete_booking assumed CASCADE and
-- skipped explicit deletion of those rows, causing the FK violation error.
--
-- Changes:
--   1. Add booking_images_data column to deleted_bookings (archive images)
--   2. Replace admin_delete_booking — archives then explicitly deletes booking_images
--   3. Replace admin_restore_booking — restores booking_images from snapshot
--   4. Replace admin_fetch_deleted_booking_detail — includes booking_images
--   5. Add admin_permanently_delete_booking — hard-purge a single archive row
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Add booking_images_data to archive table ───────────────────────────────

ALTER TABLE public.deleted_bookings
  ADD COLUMN IF NOT EXISTS booking_images_data JSONB NOT NULL DEFAULT '[]';


-- ── 2. Replace admin_delete_booking ──────────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_delete_booking(UUID);

CREATE OR REPLACE FUNCTION public.admin_delete_booking(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking_number TEXT;
BEGIN
  PERFORM fn_assert_active_admin();

  SELECT booking_number
    INTO v_booking_number
    FROM bookings
   WHERE id = p_booking_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking % not found', p_booking_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Archive all related data before any deletion ────────────────────────────
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
    refund_requests_data,
    booking_images_data
  )
  SELECT
    b.id,
    b.booking_number,
    auth.uid(),

    to_jsonb(b),

    COALESCE(
      (SELECT jsonb_agg(to_jsonb(bi))
         FROM booking_items bi WHERE bi.booking_id = b.id),
      '[]'::jsonb
    ),

    COALESCE(
      (SELECT jsonb_agg(to_jsonb(ba))
         FROM booking_addons ba WHERE ba.booking_id = b.id),
      '[]'::jsonb
    ),

    COALESCE(
      (SELECT jsonb_agg(to_jsonb(bp))
         FROM booking_payments bp WHERE bp.booking_id = b.id),
      '[]'::jsonb
    ),

    COALESCE(
      (SELECT jsonb_agg(to_jsonb(basm))
         FROM booking_assignments basm WHERE basm.booking_id = b.id),
      '[]'::jsonb
    ),

    COALESCE(
      (SELECT jsonb_agg(to_jsonb(vsb))
         FROM vendor_settlement_bookings vsb WHERE vsb.booking_id = b.id),
      '[]'::jsonb
    ),

    COALESCE(
      (SELECT jsonb_agg(to_jsonb(cr))
         FROM customer_reviews cr WHERE cr.booking_id = b.id),
      '[]'::jsonb
    ),

    COALESCE(
      (SELECT jsonb_agg(to_jsonb(sw))
         FROM service_warranties sw WHERE sw.booking_id = b.id),
      '[]'::jsonb
    ),

    COALESCE(
      (SELECT jsonb_agg(to_jsonb(cs))
         FROM call_sessions cs WHERE cs.booking_id = b.id),
      '[]'::jsonb
    ),

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
       FROM refund_requests rr WHERE rr.booking_id = b.id),
      '[]'::jsonb
    ),

    -- booking_images (archived so they can be restored with the booking)
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(img))
         FROM booking_images img WHERE img.booking_id = b.id),
      '[]'::jsonb
    )

  FROM bookings b
  WHERE b.id = p_booking_id;

  -- ── Delete dependents that block booking deletion ───────────────────────────

  -- refund_transactions → refund_requests → bookings (NO ACTION chain)
  DELETE FROM refund_transactions
   WHERE refund_request_id IN (
     SELECT id FROM refund_requests WHERE booking_id = p_booking_id
   );
  DELETE FROM refund_requests WHERE booking_id = p_booking_id;

  -- vendor_settlement_bookings (RESTRICT FK to bookings)
  DELETE FROM vendor_settlement_bookings WHERE booking_id = p_booking_id;

  -- customer_reviews (NO ACTION FK to bookings)
  DELETE FROM customer_reviews WHERE booking_id = p_booking_id;

  -- booking_items (FK behavior uncertain, treated as RESTRICT)
  DELETE FROM booking_items WHERE booking_id = p_booking_id;

  -- booking_images: fk_booking_images_booking constraint does NOT cascade,
  -- so must be removed explicitly before the booking row is deleted.
  DELETE FROM booking_images WHERE booking_id = p_booking_id;

  -- ── Delete the booking ──────────────────────────────────────────────────────
  -- Remaining FK children (booking_addons, booking_payments, booking_assignments,
  -- call_sessions, service_warranties, vendor_location_logs,
  -- gps_cancellation_audits) cascade automatically.
  -- SET NULL children (loyalty_transactions, amc_scheduling_requests,
  -- service_warranties.rework_booking_id) are handled automatically.
  DELETE FROM bookings WHERE id = p_booking_id;

  RETURN jsonb_build_object(
    'success',        true,
    'booking_id',     p_booking_id,
    'booking_number', v_booking_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_booking(UUID) TO authenticated;


-- ── 3. Replace admin_restore_booking (adds booking_images restore) ────────────

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

  -- Core booking row (critical — failure rolls back entire function)
  INSERT INTO bookings
  SELECT * FROM jsonb_populate_record(null::bookings, v_archived.booking_data);

  UPDATE bookings
     SET booking_number = v_booking_number
   WHERE id = p_booking_id
     AND booking_number IS DISTINCT FROM v_booking_number;

  -- booking_items (with FK fallback for deleted catalog nodes)
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

  -- booking_images (rows point to still-valid storage URLs)
  BEGIN
    IF jsonb_array_length(COALESCE(v_archived.booking_images_data, '[]'::jsonb)) > 0 THEN
      INSERT INTO booking_images
      SELECT * FROM jsonb_populate_recordset(
        null::booking_images, v_archived.booking_images_data
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'booking_images restore skipped for %: %', p_booking_id, SQLERRM;
  END;

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

  DELETE FROM deleted_bookings WHERE booking_id = p_booking_id;

  RETURN jsonb_build_object(
    'success',        true,
    'booking_id',     p_booking_id,
    'booking_number', v_booking_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_restore_booking(UUID) TO authenticated;


-- ── 4. Replace admin_fetch_deleted_booking_detail (include booking_images) ────

CREATE OR REPLACE FUNCTION public.admin_fetch_deleted_booking_detail(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_archived deleted_bookings%ROWTYPE;
BEGIN
  PERFORM fn_assert_active_admin();

  SELECT * INTO v_archived
    FROM deleted_bookings
   WHERE booking_id = p_booking_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deleted booking % not found in archive', p_booking_id
      USING ERRCODE = 'P0002';
  END IF;

  RETURN
    v_archived.booking_data
    || jsonb_build_object(
         'customers', (
           SELECT jsonb_build_object('full_name', c.full_name, 'phone', c.phone)
             FROM customers c
            WHERE c.id = (v_archived.booking_data->>'customer_id')::uuid
         ),
         'vendors', CASE
           WHEN v_archived.booking_data->>'vendor_id' IS NULL THEN NULL
           ELSE COALESCE(
             (SELECT jsonb_build_object('id', v.id::text, 'business_name', v.business_name)
                FROM vendors v
               WHERE v.id = (v_archived.booking_data->>'vendor_id')::uuid),
             jsonb_build_object(
               'id',            v_archived.booking_data->>'vendor_id',
               'business_name', NULL
             )
           )
         END,
         'booking_items',    COALESCE(v_archived.booking_items_data,    '[]'::jsonb),
         'booking_addons',   COALESCE(v_archived.booking_addons_data,   '[]'::jsonb),
         'customer_reviews', COALESCE(v_archived.customer_reviews_data, '[]'::jsonb),
         'booking_images',   COALESCE(v_archived.booking_images_data,   '[]'::jsonb),
         'amc_contracts',    NULL
       );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_fetch_deleted_booking_detail(UUID) TO authenticated;


-- ── 5. New RPC: permanently delete a single booking from the restore bin ───────

DROP FUNCTION IF EXISTS public.admin_permanently_delete_booking(UUID);

CREATE OR REPLACE FUNCTION public.admin_permanently_delete_booking(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking_number TEXT;
BEGIN
  PERFORM fn_assert_active_admin();

  SELECT booking_number
    INTO v_booking_number
    FROM deleted_bookings
   WHERE booking_id = p_booking_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deleted booking % not found in archive', p_booking_id
      USING ERRCODE = 'P0002';
  END IF;

  DELETE FROM deleted_bookings WHERE booking_id = p_booking_id;

  RETURN jsonb_build_object(
    'success',        true,
    'booking_id',     p_booking_id,
    'booking_number', v_booking_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_permanently_delete_booking(UUID) TO authenticated;
