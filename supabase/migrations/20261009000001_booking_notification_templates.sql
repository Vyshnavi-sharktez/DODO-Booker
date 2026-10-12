-- Migration: Dynamic booking notification templates
--
-- Creates the booking_notification_templates table (one row per booking status),
-- seeds default templates for all statuses, and installs a trigger that reads
-- the active template when a booking status changes, resolves dynamic field
-- placeholders ({customer_name}, {service_name}, etc.), and inserts a
-- notifications row (which fires the existing FCM push trigger automatically).
--
-- Also collapses old hardcoded customer notifications:
--   • Drops trg_notify_customer_vendor_assigned (superseded by 'assigned' template).
--   • Rewrites fn_notify_admin_booking_status_change to remove customer INSERTs
--     for cancellation cases (now handled by the 'cancelled' template).
--
-- Everything is in a single transaction — if any step fails the whole migration
-- rolls back, keeping the system in a consistent state.

-- ── Table ─────────────────────────────────────────────────────────────────────

CREATE TABLE booking_notification_templates (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  status_key           TEXT        NOT NULL UNIQUE,
  display_name         TEXT        NOT NULL,
  notification_title   TEXT        NOT NULL,
  notification_message TEXT        NOT NULL,
  is_enabled           BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order           INT         NOT NULL DEFAULT 0,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN booking_notification_templates.status_key IS
  'Immutable internal booking status identifier (e.g. pending, accepted).';
COMMENT ON COLUMN booking_notification_templates.notification_message IS
  'Supports placeholders: {customer_name} {service_name} {booking_id} '
  '{booking_date} {booking_time} {vendor_name} {cancelled_by}';

-- ── Default templates ─────────────────────────────────────────────────────────

INSERT INTO booking_notification_templates
  (status_key, display_name, notification_title, notification_message, sort_order)
VALUES
  (
    'pending', 'Awaiting Confirmation',
    'Booking Received',
    'Hi {customer_name}, your booking #{booking_id} for {service_name} on {booking_date} has been received. We will confirm it shortly.',
    1
  ),
  (
    'assigned', 'Vendor Assigned',
    'Service Provider Assigned',
    'Hi {customer_name}, your booking #{booking_id} has been assigned to {vendor_name}. They will be in touch before your visit.',
    2
  ),
  (
    'assigned_to_dodo_team', 'DODO Team Assigned',
    'Our Team is On It',
    'Hi {customer_name}, our DODO team has been assigned to your booking #{booking_id} for {service_name} on {booking_date}.',
    3
  ),
  (
    'accepted', 'Booking Accepted',
    'Booking Confirmed',
    'Hi {customer_name}, your booking #{booking_id} for {service_name} on {booking_date} at {booking_time} has been confirmed.',
    4
  ),
  (
    'en_route', 'Provider En Route',
    'Your Provider is On the Way',
    'Hi {customer_name}, your service provider {vendor_name} is on the way for your booking #{booking_id}.',
    5
  ),
  (
    'in_progress', 'Service In Progress',
    'Service Started',
    'Hi {customer_name}, the service for your booking #{booking_id} has started.',
    6
  ),
  (
    'awaiting_verification', 'Awaiting OTP Verification',
    'Verify Service Completion',
    'Hi {customer_name}, your service is complete. Please verify with the 4-digit OTP to close booking #{booking_id}.',
    7
  ),
  (
    'completed', 'Completed',
    'Service Completed',
    'Hi {customer_name}, your booking #{booking_id} for {service_name} is complete. Thank you for choosing DODO!',
    8
  ),
  (
    'rejected', 'Rejected by Provider',
    'Booking Could Not Be Fulfilled',
    'Hi {customer_name}, unfortunately your booking #{booking_id} could not be fulfilled by the service provider. Please reach out to our support team.',
    9
  ),
  (
    'cancelled', 'Cancelled',
    'Booking Cancelled',
    'Hi {customer_name}, your booking #{booking_id} has been cancelled.',
    10
  )
ON CONFLICT (status_key) DO NOTHING;

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE booking_notification_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bnt_admin_all"
  ON booking_notification_templates FOR ALL TO authenticated
  USING     (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid()))
  WITH CHECK(EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid()));

-- ── RPC: fetch all templates ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_booking_notification_templates()
RETURNS SETOF booking_notification_templates
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM booking_notification_templates ORDER BY sort_order, status_key;
$$;

-- ── RPC: update a single template ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_booking_notification_template(
  p_status_key           TEXT,
  p_display_name         TEXT    DEFAULT NULL,
  p_notification_title   TEXT    DEFAULT NULL,
  p_notification_message TEXT    DEFAULT NULL,
  p_is_enabled           BOOLEAN DEFAULT NULL
)
RETURNS booking_notification_templates
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_result booking_notification_templates;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE booking_notification_templates
  SET
    display_name         = COALESCE(p_display_name,           display_name),
    notification_title   = COALESCE(p_notification_title,     notification_title),
    notification_message = COALESCE(p_notification_message,   notification_message),
    is_enabled           = COALESCE(p_is_enabled,             is_enabled),
    updated_at           = NOW()
  WHERE status_key = p_status_key
  RETURNING * INTO v_result;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Template not found: %', p_status_key;
  END IF;

  RETURN v_result;
END;
$$;

-- ── Trigger function: template-driven customer push notifications ──────────────
--
-- Fires AFTER INSERT OR UPDATE OF status ON bookings.
-- Reads the matching booking_notification_templates row, resolves field
-- placeholders from live booking data, then inserts one notifications row
-- (which the existing trg_send_push_on_notification_insert picks up and
-- delivers via FCM automatically).
--
-- Idempotency: the INSERT is guarded by an EXISTS check on entity_id + type,
-- so concurrent requests or retried UPDATE calls never double-deliver.
--
-- Failure isolation: the entire body is wrapped in EXCEPTION WHEN OTHERS so a
-- notification error can never roll back the underlying booking status update.

CREATE OR REPLACE FUNCTION fn_notify_customer_booking_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template       RECORD;
  v_customer_name  TEXT;
  v_service_name   TEXT;
  v_vendor_name    TEXT;
  v_booking_num    TEXT;
  v_service_date   TEXT;
  v_scheduled_time TEXT;
  v_cancelled_by   TEXT;
  v_title          TEXT;
  v_message        TEXT;
BEGIN
  -- On UPDATE: skip when status is unchanged.
  IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  -- Fetch the template for the new status.
  SELECT * INTO v_template
  FROM   booking_notification_templates
  WHERE  status_key = NEW.status;

  -- No template or disabled → nothing to do.
  IF NOT FOUND OR NOT v_template.is_enabled THEN
    RETURN NEW;
  END IF;

  -- Idempotency guard: one customer notification per booking per status.
  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE  entity_type       = 'booking'
      AND  entity_id         = NEW.id
      AND  notification_type = 'booking_status_' || NEW.status
      AND  user_type         = 'customer'
  ) THEN
    RETURN NEW;
  END IF;

  -- ── Resolve field placeholders ─────────────────────────────────────────────

  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'Customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'Customer');

  SELECT cn.name INTO v_service_name
  FROM   booking_items bi
  JOIN   catalog_nodes  cn ON cn.id = bi.catalog_node_id
  WHERE  bi.booking_id = NEW.id
  LIMIT  1;
  v_service_name := COALESCE(v_service_name, 'Service');

  IF NEW.vendor_id IS NOT NULL THEN
    SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'the provider')
    INTO   v_vendor_name
    FROM   vendors
    WHERE  id = NEW.vendor_id;
  END IF;
  v_vendor_name := COALESCE(v_vendor_name, 'the provider');

  v_booking_num := COALESCE(NEW.booking_number, 'BK-' || UPPER(LEFT(NEW.id::TEXT, 8)));

  v_service_date := CASE
    WHEN NEW.service_date IS NOT NULL THEN TO_CHAR(NEW.service_date, 'DD Mon YYYY')
    ELSE ''
  END;

  v_scheduled_time := COALESCE(NEW.scheduled_time, '');

  -- {cancelled_by} resolves to a human phrase used in cancellation messages.
  v_cancelled_by := CASE NEW.cancelled_by
    WHEN 'admin'  THEN 'our team'
    WHEN 'vendor' THEN 'the service provider'
    ELSE ''
  END;

  -- ── Substitute placeholders ────────────────────────────────────────────────

  v_title   := v_template.notification_title;
  v_message := v_template.notification_message;

  v_title   := REPLACE(v_title,   '{customer_name}',  v_customer_name);
  v_title   := REPLACE(v_title,   '{service_name}',   v_service_name);
  v_title   := REPLACE(v_title,   '{booking_id}',     v_booking_num);
  v_title   := REPLACE(v_title,   '{booking_date}',   v_service_date);
  v_title   := REPLACE(v_title,   '{booking_time}',   v_scheduled_time);
  v_title   := REPLACE(v_title,   '{vendor_name}',    v_vendor_name);
  v_title   := REPLACE(v_title,   '{cancelled_by}',   v_cancelled_by);

  v_message := REPLACE(v_message, '{customer_name}',  v_customer_name);
  v_message := REPLACE(v_message, '{service_name}',   v_service_name);
  v_message := REPLACE(v_message, '{booking_id}',     v_booking_num);
  v_message := REPLACE(v_message, '{booking_date}',   v_service_date);
  v_message := REPLACE(v_message, '{booking_time}',   v_scheduled_time);
  v_message := REPLACE(v_message, '{vendor_name}',    v_vendor_name);
  v_message := REPLACE(v_message, '{cancelled_by}',   v_cancelled_by);

  -- ── Insert notification row (FCM push fires automatically) ─────────────────

  INSERT INTO notifications (
    user_type, user_id,
    title,    message,
    notification_type,
    entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'customer', NEW.customer_id,
    v_title,   v_message,
    'booking_status_' || NEW.status,
    'booking', NEW.id,
    FALSE, NOW()
  );

  RAISE LOG '[DODO][BookingNotif] Sent % notification for booking % → customer %',
    NEW.status, NEW.id, NEW.customer_id;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- Notification failure must not roll back the booking status update.
  RAISE LOG '[DODO][BookingNotif] Error for booking % status %: % (%)',
    NEW.id, NEW.status, SQLERRM, SQLSTATE;
  RETURN NEW;
END;
$$;

-- ── Install new trigger ───────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_notify_customer_booking_status_change ON bookings;

CREATE TRIGGER trg_notify_customer_booking_status_change
  AFTER INSERT OR UPDATE OF status ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_customer_booking_status_change();

-- ── Remove superseded vendor-assignment customer notification ─────────────────
-- The 'assigned' status template now covers this notification.
-- We drop the trigger; the vendor-assignment function itself is also dropped
-- to avoid dead code.

DROP TRIGGER   IF EXISTS trg_notify_customer_vendor_assigned ON bookings;
DROP FUNCTION  IF EXISTS fn_notify_customer_vendor_assigned();

-- ── Rewrite cancellation trigger: keep admin/vendor, drop customer INSERTs ────
-- Customer cancellation notifications are now handled by the 'cancelled'
-- status template above.  Admin and vendor notifications remain hardcoded here
-- because they carry operational context (who cancelled, why) that is outside
-- the customer-facing template scope.

CREATE OR REPLACE FUNCTION fn_notify_admin_booking_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name TEXT;
  v_booking_num   TEXT;
  v_reason_clause TEXT;
  v_message       TEXT;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('cancelled', 'cancelled_by_customer', 'completed', 'rejected') THEN
    RETURN NEW;
  END IF;

  -- Common lookups.
  SELECT COALESCE(NULLIF(TRIM(full_name), ''), 'A customer')
  INTO   v_customer_name
  FROM   customers
  WHERE  id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  v_booking_num := COALESCE(NEW.booking_number, LEFT(NEW.id::TEXT, 8));

  -- ── COMPLETED — admin notification only ────────────────────────────────────
  IF NEW.status = 'completed' THEN
    IF EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_completed'
    ) THEN RETURN NEW; END IF;

    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'admin', NULL,
      'Booking Completed',
      'Booking #' || v_booking_num || ' by ' || v_customer_name || ' has been completed.',
      'booking_completed', 'booking', NEW.id, FALSE, NOW()
    );
    RETURN NEW;
  END IF;

  -- ── REJECTED — admin notification only ────────────────────────────────────
  IF NEW.status = 'rejected' THEN
    IF EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_rejected'
    ) THEN RETURN NEW; END IF;

    v_message := 'Booking #' || v_booking_num || ' was rejected by the vendor.';
    IF NEW.rejection_reason IS NOT NULL AND TRIM(NEW.rejection_reason) <> '' THEN
      v_message := v_message || ' Reason: ' || TRIM(NEW.rejection_reason) || '.';
    END IF;

    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'admin', NULL, 'Booking Rejected', v_message,
      'booking_rejected', 'booking', NEW.id, FALSE, NOW()
    );
    RETURN NEW;
  END IF;

  -- ── CANCELLED ──────────────────────────────────────────────────────────────
  -- Build optional reason suffix (shared across messages).
  v_reason_clause := CASE
    WHEN NEW.cancellation_reason IS NOT NULL
         AND TRIM(NEW.cancellation_reason) <> ''
    THEN ' Reason: ' || TRIM(NEW.cancellation_reason) || '.'
    ELSE ''
  END;

  -- ADMIN cancelled: notify customer (via template trigger) + vendor + skip admin.
  IF NEW.cancelled_by = 'admin' THEN
    -- Vendor (personal, if assigned).
    IF NEW.vendor_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM notifications
         WHERE entity_type = 'booking' AND entity_id = NEW.id
           AND notification_type = 'booking_cancelled' AND user_type = 'vendor'
       )
    THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'vendor', NEW.vendor_id,
        'Booking Cancelled',
        'Booking #' || v_booking_num || ' has been cancelled by the team.' || v_reason_clause,
        'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
      );
    END IF;
    RETURN NEW;
  END IF;

  -- VENDOR cancelled: notify admin (broadcast) + customer (via template trigger).
  IF NEW.cancelled_by = 'vendor' THEN
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE entity_type = 'booking' AND entity_id = NEW.id
        AND notification_type = 'booking_cancelled' AND user_type = 'admin'
    ) THEN
      INSERT INTO notifications (
        user_type, user_id, title, message,
        notification_type, entity_type, entity_id, is_read, created_at
      ) VALUES (
        'admin', NULL,
        'Booking Cancelled',
        'Booking #' || v_booking_num || ' by ' || v_customer_name ||
          ' was cancelled by the vendor.' || v_reason_clause,
        'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
      );
    END IF;
    RETURN NEW;
  END IF;

  -- CUSTOMER cancelled (or legacy cancelled_by_customer / NULL):
  -- notify admin (broadcast) + vendor (if assigned).  Customer already
  -- performed the action; template trigger sends them a confirmation.
  IF NOT EXISTS (
    SELECT 1 FROM notifications
    WHERE entity_type = 'booking' AND entity_id = NEW.id
      AND notification_type = 'booking_cancelled' AND user_type = 'admin'
  ) THEN
    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'admin', NULL,
      'Booking Cancelled',
      'Booking #' || v_booking_num || ' by ' || v_customer_name || ' was cancelled.',
      'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
    );
  END IF;

  IF NEW.vendor_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM notifications
       WHERE entity_type = 'booking' AND entity_id = NEW.id
         AND notification_type = 'booking_cancelled' AND user_type = 'vendor'
     )
  THEN
    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'vendor', NEW.vendor_id,
      'Booking Cancelled',
      'Booking #' || v_booking_num || ' has been cancelled by the customer.',
      'booking_cancelled', 'booking', NEW.id, FALSE, NOW()
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Recreate trigger (function body changed; trigger definition unchanged).
DROP TRIGGER IF EXISTS trg_notify_admin_booking_status_change ON bookings;
CREATE TRIGGER trg_notify_admin_booking_status_change
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_admin_booking_status_change();
