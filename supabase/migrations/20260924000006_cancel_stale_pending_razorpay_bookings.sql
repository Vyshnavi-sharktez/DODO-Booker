-- ─────────────────────────────────────────────────────────────────────────────
-- Cancel stale pending Razorpay bookings (> 24 h, payment unverified)
--
-- Migration 20260924000005 missed bookings that have a booking_payments row
-- with status='pending' — i.e. a Razorpay order was created but the SDK never
-- reported success or failure (app killed, network dropped, etc.) and the
-- payment.failed webhook never fired.
--
-- Razorpay payment sessions expire in minutes.  Any online booking older than
-- 24 hours whose payment_status is not 'success' is definitively stale — there
-- is no possible path for the payment to complete.  Cancel them unconditionally.
--
-- Safe because:
--   - If Razorpay captured the payment, the payment.captured webhook would have
--     already set bookings.payment_status = 'success' (excluded by the WHERE).
--   - 24 hours is orders of magnitude beyond the Razorpay session TTL (~15 min).
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.bookings
   SET status         = 'cancelled',
       payment_status = 'failed',
       cancelled_by   = 'system'
 WHERE payment_method IN ('razorpay', 'online')
   AND status         = 'pending'
   AND COALESCE(payment_status, '') <> 'success'
   AND created_at     < NOW() - INTERVAL '24 hours';
