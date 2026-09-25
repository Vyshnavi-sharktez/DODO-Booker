-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: fn_auto_create_cancellation_refund_request — INSERT column/value mismatch
--
-- Bug (migration 20260923000015): the INSERT into refund_requests listed 14
-- columns but supplied only 13 values.  `v_payment_amount` for `approved_amount`
-- was missing, leaving `now()` in position 13 and `reviewed_at` with no value.
-- PostgreSQL validates PL/pgSQL bodies at call-time (not CREATE time), so the
-- function was created successfully but raised:
--   "INSERT has more target columns than expressions"
-- on every cancellation of an online-paid booking.
--
-- Fix: add the missing `v_payment_amount` expression at position 13 so that
-- approved_amount = v_payment_amount and reviewed_at = now() as intended.
--
-- Recovery block (idempotent): back-fills a refund_request for any cancelled
-- online-paid booking that has payment_status = 'success' but no refund_request
-- row yet (i.e. bookings whose trigger ran during the broken window).
-- The same idempotency guard as the trigger (EXISTS check) prevents duplicates
-- if this migration is re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Replace the trigger function with the corrected INSERT ─────────────────

CREATE OR REPLACE FUNCTION fn_auto_create_cancellation_refund_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_request_id        UUID;
  v_ticket_number     TEXT;
  v_payment_id        UUID;
  v_payment_amount    NUMERIC;
  v_category_id       UUID;
  v_customer_name     TEXT;
  v_booking_ref       TEXT;
BEGIN
  -- Idempotency: skip if any refund_request already exists for this booking.
  IF EXISTS (
    SELECT 1 FROM refund_requests WHERE booking_id = NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  -- Resolve the most recent successful booking_payment for amount + id.
  SELECT bp.id, bp.amount
    INTO v_payment_id, v_payment_amount
    FROM booking_payments bp
   WHERE bp.booking_id = NEW.id
     AND bp.status = 'success'
   ORDER BY bp.attempt_number DESC
   LIMIT 1;

  -- Fall back to booking total if no booking_payments row found.
  v_payment_amount := COALESCE(v_payment_amount, NEW.total_amount);

  -- Sanity check: nothing to refund if amount is zero or negative.
  IF v_payment_amount <= 0 THEN
    RETURN NEW;
  END IF;

  -- Resolve issue category for cancellation (nullable if seed not yet applied).
  SELECT id INTO v_category_id
    FROM refund_issue_categories
   WHERE key = 'booking_cancelled_by_customer'
   LIMIT 1;

  -- Create the refund request in 'approved' state.
  -- FIX: added the missing v_payment_amount expression for approved_amount
  --      (was absent in 20260923000015, causing the column/value count mismatch).
  INSERT INTO refund_requests (
    ticket_number,
    booking_id,
    customer_id,
    payment_id,
    issue_category_id,
    description,
    requested_amount,
    evidence_urls,
    evidence_count,
    payment_method_snapshot,
    amount_paid_snapshot,
    status,
    approved_amount,
    reviewed_at
  ) VALUES (
    '',
    NEW.id,
    NEW.customer_id,
    v_payment_id,
    v_category_id,
    'Auto-generated: booking cancelled — online payment refund.',
    v_payment_amount,
    '[]'::JSONB,
    0,
    'online',
    v_payment_amount,
    'approved',
    v_payment_amount,
    now()
  )
  RETURNING id, ticket_number INTO v_request_id, v_ticket_number;

  -- History entry (NULL → approved, system).
  -- This fires fn_notify_on_refund_status_history_insert which sends the
  -- customer a "Refund Approved" push notification.
  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status,
    changed_by, changed_by_type,
    notes
  ) VALUES (
    v_request_id, NULL, 'approved',
    NULL, 'system',
    'Booking cancelled — refund auto-approved.'
  );

  -- Admin broadcast notification.
  v_booking_ref := COALESCE(
    NEW.booking_number,
    'BK-' || UPPER(LEFT(NEW.id::TEXT, 8))
  );

  SELECT COALESCE(NULLIF(TRIM(c.full_name), ''), 'A customer')
    INTO v_customer_name
    FROM customers c
   WHERE c.id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  INSERT INTO notifications (
    user_type, user_id,
    title, message,
    notification_type, entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'admin', NULL,
    'Cancellation Refund Required',
    'Booking #' || v_booking_ref
      || ' (' || v_customer_name || ') was cancelled'
      || ' — ₹' || ROUND(v_payment_amount, 0)::TEXT
      || ' online payment needs Razorpay refund ('
      || v_ticket_number || ').',
    'cancellation_refund_pending', 'refund_request', v_request_id,
    FALSE, NOW()
  );

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][Refund] fn_auto_create_cancellation_refund_request failed '
              'for booking %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

-- ── 2. Recovery: back-fill refund_requests for bookings cancelled during the
--      broken window (trigger fired but no row was created).
--
-- Runs the same logic inline, without invoking the trigger.
-- Idempotent: skips any booking that already has a refund_request.
-- Only targets: status IN ('cancelled','cancelled_by_customer')
--             + payment_status = 'success'
--             + payment_method IN ('online','razorpay')
--             + no existing refund_request row
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  rec             RECORD;
  v_request_id    UUID;
  v_ticket_number TEXT;
  v_payment_id    UUID;
  v_payment_amount NUMERIC;
  v_category_id   UUID;
  v_customer_name TEXT;
  v_booking_ref   TEXT;
BEGIN
  -- Resolve the cancellation issue category once.
  SELECT id INTO v_category_id
    FROM refund_issue_categories
   WHERE key = 'booking_cancelled_by_customer'
   LIMIT 1;

  FOR rec IN
    SELECT b.id, b.customer_id, b.booking_number, b.total_amount
      FROM bookings b
     WHERE b.status IN ('cancelled', 'cancelled_by_customer')
       AND b.payment_status = 'success'
       AND b.payment_method IN ('online', 'razorpay')
       AND NOT EXISTS (
         SELECT 1 FROM refund_requests rr WHERE rr.booking_id = b.id
       )
  LOOP
    -- Resolve payment amount from booking_payments, fall back to total_amount.
    SELECT bp.id, bp.amount
      INTO v_payment_id, v_payment_amount
      FROM booking_payments bp
     WHERE bp.booking_id = rec.id
       AND bp.status = 'success'
     ORDER BY bp.attempt_number DESC
     LIMIT 1;

    v_payment_amount := COALESCE(v_payment_amount, rec.total_amount);

    IF v_payment_amount <= 0 THEN
      CONTINUE;
    END IF;

    INSERT INTO refund_requests (
      ticket_number,
      booking_id,
      customer_id,
      payment_id,
      issue_category_id,
      description,
      requested_amount,
      evidence_urls,
      evidence_count,
      payment_method_snapshot,
      amount_paid_snapshot,
      status,
      approved_amount,
      reviewed_at
    ) VALUES (
      '',
      rec.id,
      rec.customer_id,
      v_payment_id,
      v_category_id,
      'Auto-generated (recovery): booking cancelled — online payment refund.',
      v_payment_amount,
      '[]'::JSONB,
      0,
      'online',
      v_payment_amount,
      'approved',
      v_payment_amount,
      now()
    )
    RETURNING id, ticket_number INTO v_request_id, v_ticket_number;

    INSERT INTO refund_status_history (
      refund_request_id, from_status, to_status,
      changed_by, changed_by_type,
      notes
    ) VALUES (
      v_request_id, NULL, 'approved',
      NULL, 'system',
      'Recovery back-fill: booking was cancelled during trigger bug window.'
    );

    v_booking_ref := COALESCE(
      rec.booking_number,
      'BK-' || UPPER(LEFT(rec.id::TEXT, 8))
    );

    SELECT COALESCE(NULLIF(TRIM(c.full_name), ''), 'A customer')
      INTO v_customer_name
      FROM customers c
     WHERE c.id = rec.customer_id;
    v_customer_name := COALESCE(v_customer_name, 'A customer');

    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'admin', NULL,
      'Cancellation Refund Required (Recovered)',
      'Booking #' || v_booking_ref
        || ' (' || v_customer_name || ') was cancelled'
        || ' — ₹' || ROUND(v_payment_amount, 0)::TEXT
        || ' online payment needs Razorpay refund ('
        || v_ticket_number || ') [recovered].',
      'cancellation_refund_pending', 'refund_request', v_request_id,
      FALSE, NOW()
    );

    RAISE LOG '[DODO][Refund] Recovery: created refund_request % (%) for booking %',
      v_ticket_number, v_request_id, rec.id;
  END LOOP;
END;
$$;
