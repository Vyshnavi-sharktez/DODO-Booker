-- ─────────────────────────────────────────────────────────────────────────────
-- Razorpay assignment guard
--
-- Prevents vendor assignment of bookings whose Razorpay payment has not been
-- verified.  The root cause: booking_gate.dart creates the booking row BEFORE
-- launching the Razorpay checkout.  If payment fails or is dismissed, the
-- booking stays in the DB with payment_status = 'pending'.  Without this guard,
-- admins can dispatch those unpaid bookings to vendors.
--
-- The trigger fires BEFORE UPDATE on the bookings table and blocks any
-- transition from a non-active state (typically 'pending') into 'assigned' or
-- 'assigned_to_dodo_team' when payment_method is 'razorpay' or 'online' AND
-- payment_status is not 'success'.
--
-- Covered paths (no RPC required):
--   1. Auto-dispatch: dispatch_booking_next_tier RPC
--        UPDATE bookings SET status = 'assigned', vendor_id = ...
--   2. Manual assignment: admin bookings_repository.updateBookingAssignment()
--        UPDATE bookings SET status = 'assigned', vendor_id = ...  (direct)
--
-- Not affected:
--   – COD bookings (payment_method IN ('cod', 'cash', NULL)): guard does not apply.
--   – Updates to already-active bookings (status already 'assigned' etc.):
--     guard only fires when OLD.status is not already an active/completed state.
--   – Cancellations: 'cancelled' is not in the blocked target set.
--   – Razorpay bookings with verified payment (payment_status = 'success'):
--     the payment_status check is false; guard passes transparently.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_guard_razorpay_assignment()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Only applies to online-payment bookings.
  IF LOWER(COALESCE(NEW.payment_method, '')) NOT IN ('razorpay', 'online') THEN
    RETURN NEW;
  END IF;

  -- Block initial assignment transitions for unverified-payment bookings.
  -- Using OLD.status to restrict the guard to new assignments only — this
  -- avoids interfering with note/date updates on already-assigned bookings
  -- that pre-date this migration.
  IF NEW.status IN ('assigned', 'assigned_to_dodo_team')
     AND OLD.status NOT IN (
       'assigned', 'assigned_to_dodo_team',
       'accepted', 'en_route', 'in_progress', 'started',
       'awaiting_verification', 'completed'
     )
     AND COALESCE(NEW.payment_status, '') <> 'success'
  THEN
    RAISE EXCEPTION
      'Cannot assign booking % — Razorpay payment has not been verified '
      '(payment_status = %). Verify payment or cancel the booking first.',
      NEW.id,
      COALESCE(NEW.payment_status, 'null')
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- Drop existing trigger if present (idempotent re-run safety).
DROP TRIGGER IF EXISTS trg_guard_razorpay_assignment ON bookings;

CREATE TRIGGER trg_guard_razorpay_assignment
  BEFORE UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_guard_razorpay_assignment();
