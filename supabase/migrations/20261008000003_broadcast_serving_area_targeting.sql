-- Replaces 'city' (text-match) targeting with 'serving_area' (Haversine-based)
-- in the broadcast_notifications module.
--
-- serving_area sub-values stored in targeting_value:
--   NULL   → all customers/vendors within ANY active zone
--   <UUID> → customers/vendors within that specific zone only
--
-- Same Haversine formula used by is_location_serviceable().

-- ── 1. Migrate any existing 'city' rows before altering the constraint ────────

UPDATE broadcast_notifications
SET targeting_type = 'serving_area'
WHERE targeting_type = 'city';

-- ── 2. Update targeting_type CHECK constraint ─────────────────────────────────

ALTER TABLE broadcast_notifications
  DROP CONSTRAINT IF EXISTS broadcast_notifications_targeting_type_check;

ALTER TABLE broadcast_notifications
  ADD CONSTRAINT broadcast_notifications_targeting_type_check
  CHECK (targeting_type IN ('all', 'serving_area', 'booked_service', 'booked_category'));

-- ── 3. get_broadcast_targeting_options ───────────────────────────────────────
-- serving_area options are loaded client-side from service_availability_areas;
-- this RPC only handles booked_service and booked_category.

CREATE OR REPLACE FUNCTION get_broadcast_targeting_options(
  p_targeting_type TEXT,
  p_audience       TEXT DEFAULT 'customers'
)
RETURNS TABLE (value TEXT, label TEXT)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT DISTINCT combined.value, combined.label FROM (

    -- booked_service: catalog nodes that have at least one booking
    SELECT cn.id::TEXT AS value, cn.name AS label
    FROM catalog_nodes cn
    WHERE p_targeting_type = 'booked_service'
      AND p_audience IN ('customers', 'both')
      AND EXISTS (
        SELECT 1 FROM booking_items bi WHERE bi.service_id = cn.id
      )

    UNION

    -- booked_category: parent nodes whose children have at least one booking
    SELECT cn.id::TEXT AS value, cn.name AS label
    FROM catalog_nodes cn
    WHERE p_targeting_type = 'booked_category'
      AND p_audience IN ('customers', 'both')
      AND EXISTS (
        SELECT 1
        FROM catalog_node_relationships cnr
        JOIN booking_items bi ON bi.service_id = cnr.child_id
        WHERE cnr.parent_id = cn.id
      )

  ) AS combined
  ORDER BY label;
$$;

-- ── 4. send_broadcast_notification ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION send_broadcast_notification(p_broadcast_id UUID)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_b           broadcast_notifications%ROWTYPE;
  v_notif_type  TEXT;
  v_count       INT := 0;
  v_uid         UUID;
  v_saa_lat     NUMERIC;
  v_saa_lng     NUMERIC;
  v_saa_radius  NUMERIC;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  SELECT * INTO v_b FROM broadcast_notifications
  WHERE id = p_broadcast_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'broadcast not found';
  END IF;
  IF v_b.status NOT IN ('draft', 'scheduled') THEN
    RAISE EXCEPTION 'broadcast is already % and cannot be re-sent', v_b.status;
  END IF;

  UPDATE broadcast_notifications
  SET status = 'sending', updated_at = NOW()
  WHERE id = p_broadcast_id;

  v_notif_type := _map_broadcast_notification_type(v_b.notification_type);

  -- For a specific serving area, resolve its coordinates once.
  -- targeting_value IS NULL means "all active areas" (set by UI for that option).
  IF v_b.targeting_type = 'serving_area' AND v_b.targeting_value IS NOT NULL THEN
    SELECT latitude, longitude, radius_km
    INTO v_saa_lat, v_saa_lng, v_saa_radius
    FROM service_availability_areas
    WHERE id = v_b.targeting_value::UUID AND is_active = TRUE;
  END IF;

  -- ── customers ─────────────────────────────────────────────────────────────

  IF v_b.audience IN ('customers', 'both') THEN

    IF v_b.targeting_type = 'all' THEN
      INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
      VALUES ('customer', NULL, v_b.title, v_b.message, v_notif_type, FALSE);
      v_count := v_count + 1;

    ELSIF v_b.targeting_type = 'serving_area' THEN
      IF v_b.targeting_value IS NULL THEN
        -- All customers with any booking within ANY active serving area
        FOR v_uid IN
          SELECT DISTINCT b.customer_id
          FROM bookings b
          WHERE b.latitude IS NOT NULL AND b.longitude IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM service_availability_areas saa
              WHERE saa.is_active = TRUE
                AND (
                  6371.0 * acos(
                    LEAST(1.0,
                      cos(radians(b.latitude::FLOAT)) * cos(radians(saa.latitude::FLOAT))
                      * cos(radians(saa.longitude::FLOAT) - radians(b.longitude::FLOAT))
                      + sin(radians(b.latitude::FLOAT)) * sin(radians(saa.latitude::FLOAT))
                    )
                  )
                ) <= saa.radius_km::FLOAT
            )
        LOOP
          INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
          VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
          v_count := v_count + 1;
        END LOOP;
      ELSIF v_saa_lat IS NOT NULL THEN
        -- Customers with any booking within this specific serving area
        FOR v_uid IN
          SELECT DISTINCT b.customer_id
          FROM bookings b
          WHERE b.latitude IS NOT NULL AND b.longitude IS NOT NULL
            AND (
              6371.0 * acos(
                LEAST(1.0,
                  cos(radians(b.latitude::FLOAT)) * cos(radians(v_saa_lat::FLOAT))
                  * cos(radians(v_saa_lng::FLOAT) - radians(b.longitude::FLOAT))
                  + sin(radians(b.latitude::FLOAT)) * sin(radians(v_saa_lat::FLOAT))
                )
              )
            ) <= v_saa_radius::FLOAT
        LOOP
          INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
          VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
          v_count := v_count + 1;
        END LOOP;
      END IF;

    ELSIF v_b.targeting_type = 'booked_service' THEN
      FOR v_uid IN
        SELECT DISTINCT b.customer_id
        FROM bookings b
        JOIN booking_items bi ON bi.booking_id = b.id
        WHERE bi.service_id = v_b.targeting_value::UUID
      LOOP
        INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
        VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
        v_count := v_count + 1;
      END LOOP;

    ELSIF v_b.targeting_type = 'booked_category' THEN
      FOR v_uid IN
        SELECT DISTINCT b.customer_id
        FROM bookings b
        JOIN booking_items bi ON bi.booking_id = b.id
        JOIN catalog_node_relationships cnr ON cnr.child_id = bi.service_id
        WHERE cnr.parent_id = v_b.targeting_value::UUID
      LOOP
        INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
        VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
        v_count := v_count + 1;
      END LOOP;

    END IF;
  END IF;

  -- ── vendors ───────────────────────────────────────────────────────────────

  IF v_b.audience IN ('vendors', 'both') THEN

    IF v_b.targeting_type = 'all' THEN
      INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
      VALUES ('vendor', NULL, v_b.title, v_b.message, v_notif_type, FALSE);
      v_count := v_count + 1;

    ELSIF v_b.targeting_type = 'serving_area' THEN
      IF v_b.targeting_value IS NULL THEN
        -- Vendors within ANY active serving area
        FOR v_uid IN
          SELECT id FROM vendors
          WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND is_active = TRUE
            AND EXISTS (
              SELECT 1 FROM service_availability_areas saa
              WHERE saa.is_active = TRUE
                AND (
                  6371.0 * acos(
                    LEAST(1.0,
                      cos(radians(latitude::FLOAT)) * cos(radians(saa.latitude::FLOAT))
                      * cos(radians(saa.longitude::FLOAT) - radians(longitude::FLOAT))
                      + sin(radians(latitude::FLOAT)) * sin(radians(saa.latitude::FLOAT))
                    )
                  )
                ) <= saa.radius_km::FLOAT
            )
        LOOP
          INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
          VALUES ('vendor', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
          v_count := v_count + 1;
        END LOOP;
      ELSIF v_saa_lat IS NOT NULL THEN
        -- Vendors within this specific serving area
        FOR v_uid IN
          SELECT id FROM vendors
          WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND is_active = TRUE
            AND (
              6371.0 * acos(
                LEAST(1.0,
                  cos(radians(latitude::FLOAT)) * cos(radians(v_saa_lat::FLOAT))
                  * cos(radians(v_saa_lng::FLOAT) - radians(longitude::FLOAT))
                  + sin(radians(latitude::FLOAT)) * sin(radians(v_saa_lat::FLOAT))
                )
              )
            ) <= v_saa_radius::FLOAT
        LOOP
          INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
          VALUES ('vendor', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
          v_count := v_count + 1;
        END LOOP;
      END IF;

    -- booked_service / booked_category are customer-only; skip for vendors
    END IF;
  END IF;

  UPDATE broadcast_notifications
  SET status = 'sent',
      sent_at = NOW(),
      recipient_count = v_count,
      updated_at = NOW()
  WHERE id = p_broadcast_id;

  RETURN v_count;

EXCEPTION
  WHEN OTHERS THEN
    UPDATE broadcast_notifications
    SET status = 'failed', updated_at = NOW()
    WHERE id = p_broadcast_id;
    RAISE;
END;
$$;

-- ── 5. process_scheduled_broadcasts ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION process_scheduled_broadcasts()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_b           broadcast_notifications%ROWTYPE;
  v_notif_type  TEXT;
  v_uid         UUID;
  v_inserted    INT;
  v_total       INT := 0;
  v_saa_lat     NUMERIC;
  v_saa_lng     NUMERIC;
  v_saa_radius  NUMERIC;
BEGIN
  FOR v_b IN
    SELECT * FROM broadcast_notifications
    WHERE status = 'scheduled' AND scheduled_at <= NOW()
    ORDER BY scheduled_at
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      UPDATE broadcast_notifications
      SET status = 'sending', updated_at = NOW()
      WHERE id = v_b.id;

      v_notif_type := _map_broadcast_notification_type(v_b.notification_type);
      v_inserted   := 0;
      v_saa_lat    := NULL;
      v_saa_lng    := NULL;
      v_saa_radius := NULL;

      IF v_b.targeting_type = 'serving_area' AND v_b.targeting_value IS NOT NULL THEN
        SELECT latitude, longitude, radius_km
        INTO v_saa_lat, v_saa_lng, v_saa_radius
        FROM service_availability_areas
        WHERE id = v_b.targeting_value::UUID AND is_active = TRUE;
      END IF;

      -- customers
      IF v_b.audience IN ('customers', 'both') THEN

        IF v_b.targeting_type = 'all' THEN
          INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
          VALUES ('customer', NULL, v_b.title, v_b.message, v_notif_type, FALSE);
          v_inserted := v_inserted + 1;

        ELSIF v_b.targeting_type = 'serving_area' THEN
          IF v_b.targeting_value IS NULL THEN
            FOR v_uid IN
              SELECT DISTINCT b.customer_id FROM bookings b
              WHERE b.latitude IS NOT NULL AND b.longitude IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM service_availability_areas saa
                  WHERE saa.is_active = TRUE
                    AND (
                      6371.0 * acos(
                        LEAST(1.0,
                          cos(radians(b.latitude::FLOAT)) * cos(radians(saa.latitude::FLOAT))
                          * cos(radians(saa.longitude::FLOAT) - radians(b.longitude::FLOAT))
                          + sin(radians(b.latitude::FLOAT)) * sin(radians(saa.latitude::FLOAT))
                        )
                      )
                    ) <= saa.radius_km::FLOAT
                )
            LOOP
              INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
              VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
              v_inserted := v_inserted + 1;
            END LOOP;
          ELSIF v_saa_lat IS NOT NULL THEN
            FOR v_uid IN
              SELECT DISTINCT b.customer_id FROM bookings b
              WHERE b.latitude IS NOT NULL AND b.longitude IS NOT NULL
                AND (
                  6371.0 * acos(
                    LEAST(1.0,
                      cos(radians(b.latitude::FLOAT)) * cos(radians(v_saa_lat::FLOAT))
                      * cos(radians(v_saa_lng::FLOAT) - radians(b.longitude::FLOAT))
                      + sin(radians(b.latitude::FLOAT)) * sin(radians(v_saa_lat::FLOAT))
                    )
                  )
                ) <= v_saa_radius::FLOAT
            LOOP
              INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
              VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
              v_inserted := v_inserted + 1;
            END LOOP;
          END IF;

        ELSIF v_b.targeting_type = 'booked_service' THEN
          FOR v_uid IN
            SELECT DISTINCT b.customer_id FROM bookings b
            JOIN booking_items bi ON bi.booking_id = b.id
            WHERE bi.service_id = v_b.targeting_value::UUID
          LOOP
            INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
            VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
            v_inserted := v_inserted + 1;
          END LOOP;

        ELSIF v_b.targeting_type = 'booked_category' THEN
          FOR v_uid IN
            SELECT DISTINCT b.customer_id FROM bookings b
            JOIN booking_items bi ON bi.booking_id = b.id
            JOIN catalog_node_relationships cnr ON cnr.child_id = bi.service_id
            WHERE cnr.parent_id = v_b.targeting_value::UUID
          LOOP
            INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
            VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
            v_inserted := v_inserted + 1;
          END LOOP;

        END IF;
      END IF;

      -- vendors
      IF v_b.audience IN ('vendors', 'both') THEN

        IF v_b.targeting_type = 'all' THEN
          INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
          VALUES ('vendor', NULL, v_b.title, v_b.message, v_notif_type, FALSE);
          v_inserted := v_inserted + 1;

        ELSIF v_b.targeting_type = 'serving_area' THEN
          IF v_b.targeting_value IS NULL THEN
            FOR v_uid IN
              SELECT id FROM vendors
              WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND is_active = TRUE
                AND EXISTS (
                  SELECT 1 FROM service_availability_areas saa
                  WHERE saa.is_active = TRUE
                    AND (
                      6371.0 * acos(
                        LEAST(1.0,
                          cos(radians(latitude::FLOAT)) * cos(radians(saa.latitude::FLOAT))
                          * cos(radians(saa.longitude::FLOAT) - radians(longitude::FLOAT))
                          + sin(radians(latitude::FLOAT)) * sin(radians(saa.latitude::FLOAT))
                        )
                      )
                    ) <= saa.radius_km::FLOAT
                )
            LOOP
              INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
              VALUES ('vendor', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
              v_inserted := v_inserted + 1;
            END LOOP;
          ELSIF v_saa_lat IS NOT NULL THEN
            FOR v_uid IN
              SELECT id FROM vendors
              WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND is_active = TRUE
                AND (
                  6371.0 * acos(
                    LEAST(1.0,
                      cos(radians(latitude::FLOAT)) * cos(radians(v_saa_lat::FLOAT))
                      * cos(radians(v_saa_lng::FLOAT) - radians(longitude::FLOAT))
                      + sin(radians(latitude::FLOAT)) * sin(radians(v_saa_lat::FLOAT))
                    )
                  )
                ) <= v_saa_radius::FLOAT
            LOOP
              INSERT INTO notifications (user_type, user_id, title, message, notification_type, is_read)
              VALUES ('vendor', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
              v_inserted := v_inserted + 1;
            END LOOP;
          END IF;

        END IF;
      END IF;

      UPDATE broadcast_notifications
      SET status = 'sent',
          sent_at = NOW(),
          recipient_count = v_inserted,
          updated_at = NOW()
      WHERE id = v_b.id;

      v_total := v_total + 1;

    EXCEPTION WHEN OTHERS THEN
      UPDATE broadcast_notifications
      SET status = 'failed', updated_at = NOW()
      WHERE id = v_b.id;
      RAISE LOG 'process_scheduled_broadcasts: failed for id=%, SQLSTATE=%', v_b.id, SQLSTATE;
    END;
  END LOOP;

  RETURN v_total;
END;
$$;
