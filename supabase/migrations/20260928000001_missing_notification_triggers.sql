-- ── Missing notification triggers ─────────────────────────────────────────────
--
-- Adds four notification flows that were missing from the original schema:
--
--  1. AMC Pause submitted      → Admin broadcast (AFTER INSERT amc_pause_requests)
--  2. AMC Scheduling resolved  → Customer personal (AFTER UPDATE amc_scheduling_requests,
--                                status 'pending' → 'scheduled' or 'rejected')
--  3. AMC Contract created     → Admin broadcast + Customer personal (AFTER INSERT amc_contracts)
--  4. Loyalty points earned    → Customer personal (award_loyalty_points() updated)
--
-- Flows already covered elsewhere (no change needed):
--   - AMC Pause approved/rejected → customer: admin panel Dart code
--   - AMC Resume requested        → admin:    20260802000001 trigger
--   - AMC Resume approved/rejected→ customer: admin panel Dart code
--   - Booking created             → admin + customer: booking_service.dart
--   - Warranty claim submitted    → admin + customer: warranty_service.dart
--   - Warranty claim approved/rejected → customer: warranties_repository.dart

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. AMC PAUSE SUBMITTED → ADMIN NOTIFICATION
-- ─────────────────────────────────────────────────────────────────────────────
-- amc_pause_requests.customer_id is TEXT (no direct FK to customers).
-- Name is resolved via amc_contracts → customers chain (same pattern as resume).

CREATE OR REPLACE FUNCTION public.fn_notify_admin_amc_pause_submitted()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan_name      TEXT;
  v_customer_name  TEXT;
  v_already_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE  entity_type        = 'amc_pause_request'
      AND  entity_id          = NEW.id
      AND  notification_type  = 'amc_pause_requested'
  ) INTO v_already_exists;

  IF v_already_exists THEN
    RAISE LOG '[DODO][AMCPause] Duplicate admin notification prevented for pause request %', NEW.id;
    RETURN NEW;
  END IF;

  SELECT
    ac.plan_name,
    COALESCE(NULLIF(TRIM(cu.full_name), ''), cu.phone, 'A customer')
  INTO v_plan_name, v_customer_name
  FROM   public.amc_contracts ac
  LEFT JOIN public.customers  cu ON cu.id = ac.customer_id
  WHERE  ac.id = NEW.amc_contract_id;

  v_plan_name     := COALESCE(v_plan_name,     'an AMC plan');
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  INSERT INTO public.notifications (
    user_type, user_id, title, message,
    notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'admin',
    NULL,
    'AMC Pause Requested',
    v_customer_name || ' has requested to pause their "' || v_plan_name || '" AMC membership.' ||
      CASE WHEN NEW.reason IS NOT NULL AND TRIM(NEW.reason) <> ''
           THEN ' Reason: "' || TRIM(NEW.reason) || '".'
           ELSE ''
      END,
    'amc_pause_requested',
    'amc_pause_request',
    NEW.id,
    FALSE,
    NOW()
  );

  RAISE LOG '[DODO][AMCPause] Admin notification created for pause request % (plan: %, customer: %)',
    NEW.id, v_plan_name, v_customer_name;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_amc_pause_submitted ON public.amc_pause_requests;

CREATE TRIGGER trg_notify_admin_amc_pause_submitted
  AFTER INSERT ON public.amc_pause_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notify_admin_amc_pause_submitted();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. AMC SCHEDULING RESOLVED → CUSTOMER NOTIFICATION
-- ─────────────────────────────────────────────────────────────────────────────
-- Fires when admin changes status from 'pending' to 'scheduled' (approved) or
-- 'rejected'. amc_scheduling_requests.customer_id is UUID (direct FK to customers).

CREATE OR REPLACE FUNCTION public.fn_notify_customer_amc_scheduling_resolved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_service_name   TEXT;
  v_preferred_date TEXT;
  v_already_exists BOOLEAN;
BEGIN
  -- Only fire on pending → scheduled or pending → rejected transitions.
  IF OLD.status <> 'pending' THEN
    RETURN NEW;
  END IF;
  IF NEW.status NOT IN ('scheduled', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE  entity_type = 'amc_scheduling_request'
      AND  entity_id   = NEW.id
      AND  user_type   = 'customer'
  ) INTO v_already_exists;

  IF v_already_exists THEN
    RAISE LOG '[DODO][AMCSchedule] Duplicate customer notification prevented for request %', NEW.id;
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(TRIM(service_name), ''), 'a service')
  INTO   v_service_name
  FROM   public.amc_contracts
  WHERE  id = NEW.amc_contract_id;
  v_service_name := COALESCE(v_service_name, 'a service');

  IF NEW.preferred_date IS NOT NULL THEN
    v_preferred_date := TO_CHAR(NEW.preferred_date, 'DD Mon YYYY');
  END IF;

  IF NEW.status = 'scheduled' THEN
    INSERT INTO public.notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'customer',
      NEW.customer_id,
      'AMC Visit Scheduled',
      'Your ' || v_service_name || ' visit request has been approved and a booking has been scheduled.' ||
        CASE WHEN v_preferred_date IS NOT NULL
             THEN ' Service date: ' || v_preferred_date || '.'
             ELSE ''
        END,
      'amc_scheduling_approved',
      'amc_scheduling_request',
      NEW.id,
      FALSE,
      NOW()
    );
  ELSE
    INSERT INTO public.notifications (
      user_type, user_id, title, message,
      notification_type, entity_type, entity_id, is_read, created_at
    ) VALUES (
      'customer',
      NEW.customer_id,
      'AMC Visit Request Declined',
      'Your ' || v_service_name || ' visit request could not be scheduled at this time. You may submit a new request.',
      'amc_scheduling_rejected',
      'amc_scheduling_request',
      NEW.id,
      FALSE,
      NOW()
    );
  END IF;

  RAISE LOG '[DODO][AMCSchedule] Customer notification created for request % (status: %)',
    NEW.id, NEW.status;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_customer_amc_scheduling_resolved ON public.amc_scheduling_requests;

CREATE TRIGGER trg_notify_customer_amc_scheduling_resolved
  AFTER UPDATE OF status ON public.amc_scheduling_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notify_customer_amc_scheduling_resolved();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. AMC CONTRACT CREATED → ADMIN + CUSTOMER NOTIFICATIONS
-- ─────────────────────────────────────────────────────────────────────────────
-- Fires on every new AMC contract purchase regardless of which app path created it.
-- amc_contracts.customer_id is UUID (direct FK to customers).

CREATE OR REPLACE FUNCTION public.fn_notify_amc_contract_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name TEXT;
  v_plan_label    TEXT;
  v_already_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE  entity_type = 'amc_contract'
      AND  entity_id   = NEW.id
  ) INTO v_already_exists;

  IF v_already_exists THEN
    RAISE LOG '[DODO][AMCContract] Duplicate notification prevented for contract %', NEW.id;
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(TRIM(full_name), ''), phone, 'A customer')
  INTO   v_customer_name
  FROM   public.customers
  WHERE  id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  v_plan_label := COALESCE(
    NULLIF(TRIM(NEW.plan_name), ''),
    NULLIF(TRIM(NEW.service_name), ''),
    'AMC'
  );

  -- Admin broadcast
  INSERT INTO public.notifications (
    user_type, user_id, title, message,
    notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'admin',
    NULL,
    'New AMC Membership Purchased',
    v_customer_name || ' purchased the "' || v_plan_label || '" AMC plan.',
    'amc_contract_created',
    'amc_contract',
    NEW.id,
    FALSE,
    NOW()
  );

  -- Customer personal
  INSERT INTO public.notifications (
    user_type, user_id, title, message,
    notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'customer',
    NEW.customer_id,
    'AMC Membership Activated',
    'Your "' || v_plan_label || '" membership is now active. We''ll schedule your visits as per the plan.',
    'amc_contract_created',
    'amc_contract',
    NEW.id,
    FALSE,
    NOW()
  );

  RAISE LOG '[DODO][AMCContract] Notifications created for contract % (customer: %)',
    NEW.id, v_customer_name;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_amc_contract_created ON public.amc_contracts;

CREATE TRIGGER trg_notify_amc_contract_created
  AFTER INSERT ON public.amc_contracts
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notify_amc_contract_created();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. LOYALTY POINTS EARNED → CUSTOMER NOTIFICATION
-- ─────────────────────────────────────────────────────────────────────────────
-- Replaces award_loyalty_points() with an identical version that also inserts
-- a personal customer notification when points are awarded.
-- All existing logic (scoped catalog config → per-node columns → global fallback,
-- customer_loyalty upsert, loyalty_transactions insert) is preserved exactly.

CREATE OR REPLACE FUNCTION award_loyalty_points()
RETURNS TRIGGER AS $$
DECLARE
    s           RECORD;
    cn          RECORD;
    item_row    RECORD;
    scoped_cfg  JSONB;
    earned      INTEGER := 0;
    item_points INTEGER;
    has_items   BOOLEAN := FALSE;
BEGIN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
        SELECT * INTO s FROM loyalty_settings LIMIT 1;

        IF s.is_enabled THEN
            FOR item_row IN
                SELECT bi.service_id,
                       bi.total_price,
                       bi.catalog_parent_node_id
                FROM   booking_items bi
                WHERE  bi.booking_id = NEW.id
            LOOP
                has_items := TRUE;

                scoped_cfg := resolve_catalog_module_config(
                    'loyalty',
                    item_row.service_id,
                    item_row.catalog_parent_node_id
                );

                IF scoped_cfg IS NOT NULL THEN
                    IF (scoped_cfg->>'earn_enabled')::BOOLEAN = FALSE THEN
                        item_points := 0;
                    ELSIF scoped_cfg->>'earn_rule' = 'fixed'
                          AND (scoped_cfg->>'fixed_points') IS NOT NULL THEN
                        item_points := (scoped_cfg->>'fixed_points')::INTEGER;
                    ELSIF scoped_cfg->>'earn_rule' = 'percentage'
                          AND (scoped_cfg->>'earn_per_100') IS NOT NULL THEN
                        item_points :=
                            FLOOR(item_row.total_price / 100.0)
                            * (scoped_cfg->>'earn_per_100')::INTEGER;
                    ELSE
                        item_points :=
                            FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
                    END IF;

                ELSE
                    SELECT loyalty_earn_enabled,
                           loyalty_earn_rule,
                           loyalty_fixed_points,
                           loyalty_earn_per_100
                    INTO   cn
                    FROM   catalog_nodes
                    WHERE  id = item_row.service_id;

                    IF FOUND THEN
                        IF NOT cn.loyalty_earn_enabled THEN
                            item_points := 0;
                        ELSIF cn.loyalty_earn_rule = 'fixed'
                              AND cn.loyalty_fixed_points IS NOT NULL THEN
                            item_points := cn.loyalty_fixed_points;
                        ELSIF cn.loyalty_earn_rule = 'percentage'
                              AND cn.loyalty_earn_per_100 IS NOT NULL THEN
                            item_points :=
                                FLOOR(item_row.total_price / 100.0)
                                * cn.loyalty_earn_per_100;
                        ELSE
                            item_points :=
                                FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
                        END IF;
                    ELSE
                        item_points :=
                            FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
                    END IF;
                END IF;

                earned := earned + item_points;
            END LOOP;

            IF NOT has_items THEN
                earned := FLOOR(NEW.total_amount / 100.0) * s.earn_per_100;
            END IF;

            IF earned > 0 THEN
                INSERT INTO customer_loyalty
                    (customer_id, available_points, lifetime_earned, lifetime_redeemed)
                VALUES
                    (NEW.customer_id, earned, earned, 0)
                ON CONFLICT (customer_id) DO UPDATE SET
                    available_points = customer_loyalty.available_points + earned,
                    lifetime_earned  = customer_loyalty.lifetime_earned  + earned,
                    updated_at       = NOW();

                INSERT INTO loyalty_transactions
                    (customer_id, booking_id, transaction_type, points, description)
                VALUES
                    (NEW.customer_id, NEW.id, 'EARN', earned,
                     'Earned for booking #' || LEFT(NEW.id::TEXT, 8));

                -- Notify the customer about their earned points.
                INSERT INTO public.notifications (
                    user_type, user_id, title, message,
                    notification_type, entity_type, entity_id, is_read, created_at
                ) VALUES (
                    'customer',
                    NEW.customer_id,
                    'You''ve Earned Loyalty Points!',
                    'You earned ' || earned || ' loyalty point' ||
                      CASE WHEN earned = 1 THEN '' ELSE 's' END ||
                      ' for completing your booking. Keep booking to earn more rewards!',
                    'loyalty_points_earned',
                    'booking',
                    NEW.id,
                    FALSE,
                    NOW()
                );
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_award_loyalty_points ON bookings;
CREATE TRIGGER trg_award_loyalty_points
    AFTER UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION award_loyalty_points();
