-- ─────────────────────────────────────────────────────────────────────────────
-- Backfill existing refund_requests misclassified as COD for Razorpay bookings
--
-- When bookings.payment_method = 'razorpay', the old RPC fell through to the
-- ELSE branch and stored:
--   payment_method_snapshot = 'cash'  ← wrong, causes COD workflow
--   payment_id              = NULL    ← wrong, should reference booking_payments
--
-- This migration corrects both columns for all affected rows.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE refund_requests rr
   SET payment_method_snapshot = 'online',
       payment_id = (
         SELECT bp.id
           FROM booking_payments bp
          WHERE bp.booking_id = rr.booking_id
            AND bp.status     = 'success'
          ORDER BY bp.attempt_number DESC
          LIMIT 1
       )
  FROM bookings b
 WHERE rr.booking_id           = b.id
   AND b.payment_method        = 'razorpay'
   AND rr.payment_method_snapshot = 'cash';
