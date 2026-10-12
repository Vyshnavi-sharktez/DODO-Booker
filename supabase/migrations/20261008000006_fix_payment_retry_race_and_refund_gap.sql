-- ─────────────────────────────────────────────────────────────────────────────
-- Fix 1: fn_auto_cancel_booking_on_payment_failed
--   Guard was missing: if another booking_payments row for the SAME booking
--   already has status='success' (late async capture before the failed webhook
--   arrives), do NOT cancel the booking.
--
-- Fix 2: New trigger trg_auto_create_cancellation_refund_on_payment_verified
--   The existing trg_auto_create_cancellation_refund_request fires on
--   UPDATE OF status → 'cancelled' when payment_status is already 'success'.
--   But the race case is the reverse: booking is already 'cancelled' and the
--   Razorpay webhook later sets payment_status → 'success'.  That UPDATE OF
--   payment_status was never covered, so no refund_request was created.
--   This trigger fills that gap.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Fix 1 ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_auto_cancel_booking_on_payment_failed()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  IF NEW.status <> 'failed' THEN RETURN NEW; END IF;

  -- Don't cancel if a retry is already in-flight.
  IF EXISTS (
    SELECT 1 FROM public.booking_payments
     WHERE booking_id = NEW.booking_id
       AND id        <> NEW.id
       AND status     = 'pending'
  ) THEN
    RETURN NEW;
  END IF;

  -- Don't cancel if the payment was actually captured on another attempt.
  IF EXISTS (
    SELECT 1 FROM public.booking_payments
     WHERE booking_id = NEW.booking_id
       AND status     = 'success'
  ) THEN
    RETURN NEW;
  END IF;

  UPDATE public.bookings
     SET status         = 'cancelled',
         payment_status = 'failed',
         cancelled_by   = 'system'
   WHERE id             = NEW.booking_id
     AND status         = 'pending'
     AND payment_method IN ('razorpay', 'online')
     AND COALESCE(payment_status, '') <> 'success';

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_cancel_booking_on_payment_failed ON public.booking_payments;
CREATE TRIGGER trg_auto_cancel_booking_on_payment_failed
  AFTER UPDATE ON public.booking_payments
  FOR EACH ROW
  EXECUTE FUNCTION fn_auto_cancel_booking_on_payment_failed();

-- ── Fix 2: trigger function ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_auto_create_cancellation_refund_on_payment_verified()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_request_id     UUID;
  v_ticket_number  TEXT;
  v_payment_id     UUID;
  v_payment_amount NUMERIC;
  v_category_id    UUID;
  v_customer_name  TEXT;
  v_booking_ref    TEXT;
BEGIN
  -- Only act when payment_status transitions to 'success'
  -- AND the booking is already cancelled (the gap case).
  IF OLD.payment_status IS NOT DISTINCT FROM 'success' THEN RETURN NEW; END IF;
  IF NEW.payment_status <> 'success'                   THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('cancelled', 'cancelled_by_customer') THEN RETURN NEW; END IF;
  IF NEW.payment_method NOT IN ('online', 'razorpay')  THEN RETURN NEW; END IF;

  -- Idempotency: skip if any refund_request already exists for this booking.
  IF EXISTS (SELECT 1 FROM refund_requests WHERE booking_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  SELECT bp.id, bp.amount
    INTO v_payment_id, v_payment_amount
    FROM booking_payments bp
   WHERE bp.booking_id = NEW.id
     AND bp.status     = 'success'
   ORDER BY bp.attempt_number DESC
   LIMIT 1;

  v_payment_amount := COALESCE(v_payment_amount, NEW.total_amount);
  IF v_payment_amount <= 0 THEN RETURN NEW; END IF;

  SELECT id INTO v_category_id
    FROM refund_issue_categories
   WHERE key = 'booking_cancelled_by_customer'
   LIMIT 1;

  INSERT INTO refund_requests (
    ticket_number, booking_id, customer_id, payment_id,
    issue_category_id, description, requested_amount,
    evidence_urls, evidence_count,
    payment_method_snapshot, amount_paid_snapshot,
    status, approved_amount, reviewed_at
  ) VALUES (
    '', NEW.id, NEW.customer_id, v_payment_id,
    v_category_id,
    'Auto-generated: payment captured after booking was cancelled — refund required.',
    v_payment_amount,
    '[]'::JSONB, 0,
    'online', v_payment_amount,
    'approved', v_payment_amount, now()
  )
  RETURNING id, ticket_number INTO v_request_id, v_ticket_number;

  INSERT INTO refund_status_history (
    refund_request_id, from_status, to_status, changed_by, changed_by_type, notes
  ) VALUES (
    v_request_id, NULL, 'approved', NULL, 'system',
    'Payment captured after booking cancellation — refund auto-approved.'
  );

  v_booking_ref := COALESCE(NEW.booking_number, 'BK-' || UPPER(LEFT(NEW.id::TEXT, 8)));

  SELECT COALESCE(NULLIF(TRIM(c.full_name), ''), 'A customer')
    INTO v_customer_name
    FROM customers c WHERE c.id = NEW.customer_id;
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  INSERT INTO notifications (
    user_type, user_id, title, message,
    notification_type, entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'admin', NULL,
    'Cancellation Refund Required',
    'Booking #' || v_booking_ref || ' (' || v_customer_name || ')'
      || ' — payment of ₹' || ROUND(v_payment_amount, 0)::TEXT
      || ' was captured after cancellation. Razorpay refund required ('
      || v_ticket_number || ').',
    'cancellation_refund_pending', 'refund_request', v_request_id,
    FALSE, NOW()
  );

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][Refund] fn_auto_create_cancellation_refund_on_payment_verified '
              'failed for booking %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_create_cancellation_refund_on_payment_verified ON public.bookings;
CREATE TRIGGER trg_auto_create_cancellation_refund_on_payment_verified
  AFTER UPDATE OF payment_status ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_auto_create_cancellation_refund_on_payment_verified();
