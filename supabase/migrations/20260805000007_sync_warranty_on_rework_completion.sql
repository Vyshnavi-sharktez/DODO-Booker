-- Migration: Update service_warranties status check constraint and add completion trigger

-- 1. Drop existing CHECK constraint
ALTER TABLE public.service_warranties
  DROP CONSTRAINT IF EXISTS service_warranties_status_check;

-- 2. Add updated CHECK constraint supporting 'Resolved'
ALTER TABLE public.service_warranties
  ADD CONSTRAINT service_warranties_status_check
  CHECK (status IN ('Active', 'Expired', 'Claimed', 'Approved', 'Rejected', 'Resolved'));

-- 3. Create Trigger function to automatically mark service_warranties as 'Resolved'
--    when its linked rework_booking reaches status = 'completed'
CREATE OR REPLACE FUNCTION public.sync_warranty_status_on_rework_completed()
RETURNS TRIGGER AS $$
BEGIN
  IF (NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed')) THEN
    UPDATE public.service_warranties
    SET status = 'Resolved',
        updated_at = NOW()
    WHERE rework_booking_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_warranty_status_on_rework_completed ON public.bookings;

CREATE TRIGGER trg_sync_warranty_status_on_rework_completed
  AFTER UPDATE OF status ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_warranty_status_on_rework_completed();

-- 4. Retroactively fix existing completed rework bookings whose warranty is still 'Approved' or 'Claimed'
UPDATE public.service_warranties sw
SET status = 'Resolved',
    updated_at = NOW()
FROM public.bookings b
WHERE sw.rework_booking_id = b.id
  AND b.status = 'completed'
  AND sw.status != 'Resolved';
