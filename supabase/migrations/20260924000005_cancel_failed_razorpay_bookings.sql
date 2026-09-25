-- ─────────────────────────────────────────────────────────────────────────────
-- Cancel failed Razorpay bookings: backfill + DB-level auto-cancel trigger
--
-- Root cause: before the app-side cancellation-on-failure fix was deployed,
-- failed or dismissed Razorpay checkouts left bookings in status='pending' +
-- payment_status='pending' with no cleanup path.  The razorpay-webhook handler
-- intentionally does not touch bookings on payment.failed (to allow payment
-- retry without re-booking), so those rows were permanently stuck and showed
-- isPaymentUncertain=true in My Bookings.
--
-- Three parts:
--
--   Fix A — Backfill: cancel bookings where booking_payments.status='failed'.
--            Safe because Razorpay has confirmed the charge did not go through.
--            A booking may have multiple payment attempts; we only cancel if the
--            LATEST attempt is failed and there is no other pending attempt.
--
--   Fix B — Backfill: cancel bookings older than 24h whose payment_method is
--            razorpay/online but no booking_payments row exists (i.e. Razorpay
--            order creation never started — pure pre-checkout abandonment).
--
--   Fix C — Trigger: when booking_payments.status transitions to 'failed', the
--            trigger auto-cancels the parent booking if it is still pending.
--            This is the DB-level safety net for the app's silent catch(_){}.
--            Guard: does NOT cancel if a newer pending payment attempt exists
--            for the same booking (customer may have already started a retry).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Fix A: backfill bookings with a confirmed failed payment attempt ─────────
--
-- Conditions:
--   - Online/Razorpay booking that is still pending
--   - Has at least one booking_payments row with status='failed'
--   - Has no booking_payments row with status='pending' (no retry in-flight)
--   - payment_status is not already 'success' (idempotency guard)
UPDATE public.bookings b
   SET status         = 'cancelled',
       payment_status = 'failed',
       cancelled_by   = 'system'
 WHERE b.payment_method IN ('razorpay', 'online')
   AND b.status       = 'pending'
   AND COALESCE(b.payment_status, '') <> 'success'
   AND EXISTS (
         SELECT 1 FROM public.booking_payments bp
          WHERE bp.booking_id = b.id AND bp.status = 'failed'
       )
   AND NOT EXISTS (
         SELECT 1 FROM public.booking_payments bp
          WHERE bp.booking_id = b.id AND bp.status = 'pending'
       );

-- ── Fix B: backfill bookings abandoned before checkout (no payment row) ──────
--
-- Conditions:
--   - Online/Razorpay booking still pending, older than 24 hours
--   - No booking_payments row at all (Razorpay order was never created)
--   - payment_status is not 'success'
UPDATE public.bookings b
   SET status         = 'cancelled',
       payment_status = 'failed',
       cancelled_by   = 'system'
 WHERE b.payment_method IN ('razorpay', 'online')
   AND b.status       = 'pending'
   AND COALESCE(b.payment_status, '') <> 'success'
   AND b.created_at   < NOW() - INTERVAL '24 hours'
   AND NOT EXISTS (
         SELECT 1 FROM public.booking_payments bp
          WHERE bp.booking_id = b.id
       );

-- ── Fix C: trigger — auto-cancel booking when payment_payments flips to failed ─

CREATE OR REPLACE FUNCTION fn_auto_cancel_booking_on_payment_failed()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Only act on pending → failed transitions.
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;
  IF NEW.status <> 'failed' THEN
    RETURN NEW;
  END IF;

  -- Do NOT cancel if a separate pending attempt exists for the same booking.
  -- This means the customer has already started a retry — let it proceed.
  IF EXISTS (
    SELECT 1 FROM public.booking_payments
     WHERE booking_id = NEW.booking_id
       AND id         <> NEW.id
       AND status      = 'pending'
  ) THEN
    RETURN NEW;
  END IF;

  -- Cancel the booking only when it is still in a cancellable state.
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
