-- Add cancelled_at timestamp to vendor_subscriptions.
-- Populated automatically by trigger when status changes to 'cancelled'.

ALTER TABLE vendor_subscriptions
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION fn_set_cancelled_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'cancelled' AND (OLD.status IS DISTINCT FROM 'cancelled') THEN
    NEW.cancelled_at = NOW();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_cancelled_at ON vendor_subscriptions;
CREATE TRIGGER trg_set_cancelled_at
  BEFORE UPDATE OF status ON vendor_subscriptions
  FOR EACH ROW EXECUTE FUNCTION fn_set_cancelled_at();
