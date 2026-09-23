-- ─────────────────────────────────────────────────────────────────────────────
-- Add completed_at to bookings.
--
-- Provides a stable, tamper-resistant timestamp recording exactly when a booking
-- transitioned to 'completed'.  Used by the refund eligibility period check to
-- compute the deadline (completed_at + effective_period_days).
--
-- updated_at is not suitable because it changes on any admin edit after
-- completion.  completed_at is set once and never overwritten.
--
-- Backfill: existing completed bookings inherit updated_at as the best
-- available proxy (it equals the last write, which was typically the
-- status-change to 'completed').
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

-- ── Trigger: set completed_at once on first transition to 'completed' ─────────

CREATE OR REPLACE FUNCTION fn_set_booking_completed_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'completed'
     AND OLD.status IS DISTINCT FROM 'completed'
     AND NEW.completed_at IS NULL THEN
    NEW.completed_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_booking_completed_at ON bookings;
CREATE TRIGGER trg_booking_completed_at
  BEFORE UPDATE OF status ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_set_booking_completed_at();

-- ── Backfill ──────────────────────────────────────────────────────────────────

UPDATE bookings
   SET completed_at = updated_at
 WHERE status = 'completed'
   AND completed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_completed_at
  ON bookings (completed_at)
  WHERE completed_at IS NOT NULL;
