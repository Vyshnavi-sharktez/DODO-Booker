-- Fix broadcast_notifications rows where targeting_value was incorrectly stored
-- as the UI sentinel string 'all_areas' instead of NULL.
--
-- Root cause: the admin dialog used 'all_areas' as a UI-only sentinel for
-- "All active serving areas" but the _dbTargetingValue translation to NULL
-- was not yet applied when some drafts were saved. The send_broadcast_notification
-- function reads the stored value and attempts targeting_value::UUID, which fails
-- on the non-UUID string.
--
-- Fix: normalise all such rows to NULL (which the send function already treats
-- as "all active serving areas"), and harden both send functions with an extra
-- guard so they never attempt to cast the sentinel even if it slips through again.

-- ── 1. Data cleanup ──────────────────────────────────────────────────────────

UPDATE broadcast_notifications
SET    targeting_value = NULL,
       updated_at      = NOW()
WHERE  targeting_type = 'serving_area'
  AND  targeting_value = 'all_areas';

-- ── 2. send_broadcast_notification — defensive guard ─────────────────────────
-- Treat 'all_areas' sentinel exactly like NULL (all active zones).

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
  v_target_uuid UUID;
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

  -- Resolve specific serving area coordinates.
  -- NULL or 'all_areas' sentinel both mean "all active zones" — skip UUID cast.
  IF v_b.targeting_type = 'serving_area'
     AND v_b.targeting_value IS NOT NULL
     AND v_b.targeting_value != 'all_areas' THEN
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
      IF v_b.targeting_value IS NULL OR v_b.targeting_value = 'all_areas' THEN
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
      IF v_b.targeting_value IS NULL OR v_b.targeting_value = 'all_areas' THEN
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

-- ── 3. process_scheduled_broadcasts — same defensive guard ───────────────────

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

      IF v_b.targeting_type = 'serving_area'
         AND v_b.targeting_value IS NOT NULL
         AND v_b.targeting_value != 'all_areas' THEN
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
          IF v_b.targeting_value IS NULL OR v_b.targeting_value = 'all_areas' THEN
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
          IF v_b.targeting_value IS NULL OR v_b.targeting_value = 'all_areas' THEN
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
