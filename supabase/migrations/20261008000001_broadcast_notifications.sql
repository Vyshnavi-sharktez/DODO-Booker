-- ── broadcast_notifications ────────────────────────────────────────────────────
-- Stores admin-created notification campaigns (broadcasts) that are delivered
-- to customers and/or vendors through the existing push notification pipeline.
--
-- Sending a broadcast inserts rows into the `notifications` table, which fires
-- fn_send_push_on_notification_insert (trigger) → send-push-notification
-- (edge function) for each row.  A null user_id means "all users of that type".
--
-- Targeting types:
--   all            → single notification row with user_id=NULL (broadcast)
--   city           → vendors: vendors.city; customers: customer_addresses.city
--   booked_service → customers who booked a specific catalog_node (service_id)
--   booked_category → customers who booked any service under a parent catalog_node

CREATE TABLE broadcast_notifications (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title             TEXT        NOT NULL,
  message           TEXT        NOT NULL,
  notification_type TEXT        NOT NULL DEFAULT 'announcement'
                                CHECK (notification_type IN ('offer', 'new_service', 'announcement', 'custom')),
  audience          TEXT        NOT NULL DEFAULT 'customers'
                                CHECK (audience IN ('customers', 'vendors', 'both')),
  image_url         TEXT,
  deep_link         TEXT,
  targeting_type    TEXT        NOT NULL DEFAULT 'all'
                                CHECK (targeting_type IN ('all', 'city', 'booked_service', 'booked_category')),
  targeting_value   TEXT,
  targeting_label   TEXT,
  status            TEXT        NOT NULL DEFAULT 'draft'
                                CHECK (status IN ('draft', 'scheduled', 'sending', 'sent', 'failed')),
  scheduled_at      TIMESTAMPTZ,
  sent_at           TIMESTAMPTZ,
  recipient_count   INT         NOT NULL DEFAULT 0,
  created_by        UUID        REFERENCES admin_users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── RLS ──────────────────────────────────────────────────────────────────────

ALTER TABLE broadcast_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "broadcast_admin_all"
  ON broadcast_notifications FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE auth_user_id = auth.uid() AND is_active = TRUE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE auth_user_id = auth.uid() AND is_active = TRUE
    )
  );

-- ── Realtime ─────────────────────────────────────────────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE broadcast_notifications;

-- ── Helper: map broadcast notification_type → notifications.notification_type ─

CREATE OR REPLACE FUNCTION _map_broadcast_notification_type(p_type TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_type
    WHEN 'offer'        THEN 'promotion'
    WHEN 'new_service'  THEN 'system'
    WHEN 'announcement' THEN 'system'
    WHEN 'custom'       THEN 'system'
    ELSE 'system'
  END;
$$;

-- ── get_broadcast_targeting_options ──────────────────────────────────────────
-- Returns available {value, label} pairs for a given targeting type + audience.
-- Used to populate the targeting value dropdown in the create-notification dialog.

CREATE OR REPLACE FUNCTION get_broadcast_targeting_options(
  p_targeting_type TEXT,
  p_audience       TEXT DEFAULT 'customers'
)
RETURNS TABLE (value TEXT, label TEXT)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT DISTINCT combined.value, combined.label FROM (

    -- city: vendors
    SELECT v.city AS value, v.city AS label
    FROM vendors v
    WHERE p_targeting_type = 'city'
      AND p_audience IN ('vendors', 'both')
      AND v.city IS NOT NULL AND length(trim(v.city)) > 0
      AND v.is_active = TRUE

    UNION

    -- city: customers (from customer_addresses)
    SELECT ca.city AS value, ca.city AS label
    FROM customer_addresses ca
    JOIN customers c ON c.id = ca.customer_id
    WHERE p_targeting_type = 'city'
      AND p_audience IN ('customers', 'both')
      AND ca.city IS NOT NULL AND length(trim(ca.city)) > 0
      AND c.is_active = TRUE

    UNION

    -- booked_service: catalog nodes that have been booked (customers only)
    SELECT cn.id::TEXT AS value, cn.name AS label
    FROM catalog_nodes cn
    WHERE p_targeting_type = 'booked_service'
      AND p_audience IN ('customers', 'both')
      AND EXISTS (
        SELECT 1 FROM booking_items bi WHERE bi.service_id = cn.id
      )

    UNION

    -- booked_category: parent nodes whose children have been booked
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

GRANT EXECUTE ON FUNCTION get_broadcast_targeting_options(TEXT, TEXT) TO authenticated;

-- ── send_broadcast_notification ───────────────────────────────────────────────
-- Resolves targeting, inserts notification row(s) into `notifications` (which
-- fires the push trigger), then marks the broadcast as sent.
-- Returns the number of notification rows inserted.

CREATE OR REPLACE FUNCTION send_broadcast_notification(p_broadcast_id UUID)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_b           broadcast_notifications%ROWTYPE;
  v_notif_type  TEXT;
  v_count       INT := 0;
  v_uid         UUID;
BEGIN
  -- Admin auth check
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE auth_user_id = auth.uid() AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  -- Lock the row to prevent concurrent sends
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

  -- ── customers ─────────────────────────────────────────────────────────────

  IF v_b.audience IN ('customers', 'both') THEN
    IF v_b.targeting_type = 'all' THEN
      INSERT INTO notifications
        (user_type, user_id, title, message, notification_type, is_read)
      VALUES ('customer', NULL, v_b.title, v_b.message, v_notif_type, FALSE);
      v_count := v_count + 1;

    ELSIF v_b.targeting_type = 'city' THEN
      FOR v_uid IN
        SELECT DISTINCT ca.customer_id
        FROM customer_addresses ca
        JOIN customers c ON c.id = ca.customer_id
        WHERE LOWER(ca.city) = LOWER(v_b.targeting_value)
          AND c.is_active = TRUE
      LOOP
        INSERT INTO notifications
          (user_type, user_id, title, message, notification_type, is_read)
        VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
        v_count := v_count + 1;
      END LOOP;

    ELSIF v_b.targeting_type = 'booked_service' THEN
      FOR v_uid IN
        SELECT DISTINCT b.customer_id
        FROM bookings b
        JOIN booking_items bi ON bi.booking_id = b.id
        WHERE bi.service_id = v_b.targeting_value::UUID
      LOOP
        INSERT INTO notifications
          (user_type, user_id, title, message, notification_type, is_read)
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
        INSERT INTO notifications
          (user_type, user_id, title, message, notification_type, is_read)
        VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
        v_count := v_count + 1;
      END LOOP;
    END IF;
  END IF;

  -- ── vendors ───────────────────────────────────────────────────────────────

  IF v_b.audience IN ('vendors', 'both') THEN
    IF v_b.targeting_type = 'all' THEN
      INSERT INTO notifications
        (user_type, user_id, title, message, notification_type, is_read)
      VALUES ('vendor', NULL, v_b.title, v_b.message, v_notif_type, FALSE);
      v_count := v_count + 1;

    ELSIF v_b.targeting_type = 'city' THEN
      FOR v_uid IN
        SELECT id FROM vendors
        WHERE LOWER(city) = LOWER(v_b.targeting_value)
          AND is_active = TRUE
      LOOP
        INSERT INTO notifications
          (user_type, user_id, title, message, notification_type, is_read)
        VALUES ('vendor', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
        v_count := v_count + 1;
      END LOOP;

    -- booked_service and booked_category are customer-only; skip for vendors
    END IF;
  END IF;

  -- Mark as sent
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

GRANT EXECUTE ON FUNCTION send_broadcast_notification(UUID) TO authenticated;

-- ── process_scheduled_broadcasts ────────────────────────────────────────────
-- Called by pg_cron every minute. Fires any scheduled broadcasts whose
-- scheduled_at time has arrived. FOR UPDATE SKIP LOCKED prevents double-sends
-- under concurrent executions.

CREATE OR REPLACE FUNCTION process_scheduled_broadcasts()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_b           broadcast_notifications%ROWTYPE;
  v_notif_type  TEXT;
  v_uid         UUID;
  v_inserted    INT;
  v_total       INT := 0;
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
      v_inserted := 0;

      -- customers
      IF v_b.audience IN ('customers', 'both') THEN
        IF v_b.targeting_type = 'all' THEN
          INSERT INTO notifications
            (user_type, user_id, title, message, notification_type, is_read)
          VALUES ('customer', NULL, v_b.title, v_b.message, v_notif_type, FALSE);
          v_inserted := v_inserted + 1;

        ELSIF v_b.targeting_type = 'city' THEN
          FOR v_uid IN
            SELECT DISTINCT ca.customer_id
            FROM customer_addresses ca
            JOIN customers c ON c.id = ca.customer_id
            WHERE LOWER(ca.city) = LOWER(v_b.targeting_value) AND c.is_active = TRUE
          LOOP
            INSERT INTO notifications
              (user_type, user_id, title, message, notification_type, is_read)
            VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
            v_inserted := v_inserted + 1;
          END LOOP;

        ELSIF v_b.targeting_type = 'booked_service' THEN
          FOR v_uid IN
            SELECT DISTINCT b.customer_id FROM bookings b
            JOIN booking_items bi ON bi.booking_id = b.id
            WHERE bi.service_id = v_b.targeting_value::UUID
          LOOP
            INSERT INTO notifications
              (user_type, user_id, title, message, notification_type, is_read)
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
            INSERT INTO notifications
              (user_type, user_id, title, message, notification_type, is_read)
            VALUES ('customer', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
            v_inserted := v_inserted + 1;
          END LOOP;
        END IF;
      END IF;

      -- vendors
      IF v_b.audience IN ('vendors', 'both') THEN
        IF v_b.targeting_type = 'all' THEN
          INSERT INTO notifications
            (user_type, user_id, title, message, notification_type, is_read)
          VALUES ('vendor', NULL, v_b.title, v_b.message, v_notif_type, FALSE);
          v_inserted := v_inserted + 1;

        ELSIF v_b.targeting_type = 'city' THEN
          FOR v_uid IN
            SELECT id FROM vendors
            WHERE LOWER(city) = LOWER(v_b.targeting_value) AND is_active = TRUE
          LOOP
            INSERT INTO notifications
              (user_type, user_id, title, message, notification_type, is_read)
            VALUES ('vendor', v_uid, v_b.title, v_b.message, v_notif_type, FALSE);
            v_inserted := v_inserted + 1;
          END LOOP;
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

-- ── pg_cron: check for due scheduled broadcasts every minute ─────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'process-scheduled-broadcasts'
  ) THEN
    PERFORM cron.schedule(
      'process-scheduled-broadcasts',
      '* * * * *',
      'SELECT public.process_scheduled_broadcasts()'
    );
  END IF;
END;
$$;
