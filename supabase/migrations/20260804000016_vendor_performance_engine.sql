-- ── Vendor Performance Engine Foundation ──────────────────────────────────
-- Adds performance qualification thresholds to vendor_tiers table.
-- Adds tier_id and tier_evaluated_at columns to vendors table.
-- Defines evaluate_vendor_performance and evaluate_all_vendors_performance functions.

-- 1. Extend vendor_tiers with qualification threshold columns
ALTER TABLE public.vendor_tiers
  ADD COLUMN IF NOT EXISTS min_completed_bookings INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS min_rating NUMERIC(3,2) NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS max_cancellation_rate NUMERIC(5,2) NOT NULL DEFAULT 100.0,
  ADD COLUMN IF NOT EXISTS min_completion_rate NUMERIC(5,2) NOT NULL DEFAULT 0.0;

-- 2. Extend vendors table with tier_id and evaluation timestamp
ALTER TABLE public.vendors
  ADD COLUMN IF NOT EXISTS tier_id UUID REFERENCES public.vendor_tiers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS tier_evaluated_at TIMESTAMPTZ;

-- Index on vendors.tier_id
CREATE INDEX IF NOT EXISTS idx_vendors_tier_id ON public.vendors (tier_id);

-- 3. Core Function: evaluate_vendor_performance(p_vendor_id UUID)
CREATE OR REPLACE FUNCTION public.evaluate_vendor_performance(p_vendor_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_completed_count INT := 0;
  v_cancelled_count INT := 0;
  v_total_assigned INT := 0;
  v_avg_rating NUMERIC(3,2) := 0.0;
  v_cancellation_rate NUMERIC(5,2) := 0.0;
  v_completion_rate NUMERIC(5,2) := 0.0;
  v_matched_tier_id UUID := NULL;
  v_rec RECORD;
BEGIN
  IF p_vendor_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Calculate booking stats for this vendor
  SELECT
    COALESCE(COUNT(*) FILTER (WHERE status = 'completed'), 0),
    COALESCE(COUNT(*) FILTER (WHERE status = 'cancelled'), 0),
    COALESCE(COUNT(*) FILTER (WHERE status IN ('completed', 'cancelled', 'assigned', 'in_progress', 'accepted')), 0)
  INTO
    v_completed_count,
    v_cancelled_count,
    v_total_assigned
  FROM public.bookings
  WHERE vendor_id = p_vendor_id;

  -- Calculate rates
  IF v_total_assigned > 0 THEN
    v_cancellation_rate := ROUND((v_cancelled_count::NUMERIC / v_total_assigned::NUMERIC) * 100.0, 2);
    v_completion_rate := ROUND((v_completed_count::NUMERIC / v_total_assigned::NUMERIC) * 100.0, 2);
  ELSE
    v_cancellation_rate := 0.0;
    v_completion_rate := 0.0;
  END IF;

  -- Calculate average rating from customer_reviews (with fallback to vendors.rating)
  SELECT
    COALESCE(
      ROUND(AVG(cr.rating)::NUMERIC, 2),
      (SELECT ROUND(COALESCE(rating, 0.0)::NUMERIC, 2) FROM public.vendors WHERE id = p_vendor_id),
      0.0
    )
  INTO v_avg_rating
  FROM public.customer_reviews cr
  JOIN public.bookings b ON cr.booking_id = b.id
  WHERE b.vendor_id = p_vendor_id AND cr.rating IS NOT NULL;

  -- Match against active vendor_tiers ordered by priority ASC (Rank 1 = Highest Priority)
  FOR v_rec IN
    SELECT id, min_completed_bookings, min_rating, max_cancellation_rate, min_completion_rate
    FROM public.vendor_tiers
    WHERE is_active = true
    ORDER BY priority ASC, created_at ASC
  LOOP
    IF v_completed_count >= v_rec.min_completed_bookings AND
       v_avg_rating >= v_rec.min_rating AND
       v_cancellation_rate <= v_rec.max_cancellation_rate AND
       v_completion_rate >= v_rec.min_completion_rate THEN
      v_matched_tier_id := v_rec.id;
      EXIT; -- Matched highest priority tier
    END IF;
  END LOOP;

  -- Update vendor record
  UPDATE public.vendors
  SET
    tier_id = v_matched_tier_id,
    tier_evaluated_at = now()
  WHERE id = p_vendor_id;

  RETURN v_matched_tier_id;
END;
$$;

-- 4. Batch Function: evaluate_all_vendors_performance()
CREATE OR REPLACE FUNCTION public.evaluate_all_vendors_performance()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_vendor_id UUID;
  v_count INT := 0;
BEGIN
  FOR v_vendor_id IN SELECT id FROM public.vendors LOOP
    PERFORM public.evaluate_vendor_performance(v_vendor_id);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- 5. Targeted Database Triggers
-- Trigger function for bookings changes
CREATE OR REPLACE FUNCTION public.fn_on_booking_vendor_performance_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.vendor_id IS NOT NULL THEN
      PERFORM public.evaluate_vendor_performance(NEW.vendor_id);
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF (OLD.status IS DISTINCT FROM NEW.status OR OLD.vendor_id IS DISTINCT FROM NEW.vendor_id) THEN
      IF NEW.vendor_id IS NOT NULL THEN
        PERFORM public.evaluate_vendor_performance(NEW.vendor_id);
      END IF;
      IF OLD.vendor_id IS NOT NULL AND OLD.vendor_id IS DISTINCT FROM NEW.vendor_id THEN
        PERFORM public.evaluate_vendor_performance(OLD.vendor_id);
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_booking_vendor_performance ON public.bookings;
CREATE TRIGGER trg_booking_vendor_performance
AFTER INSERT OR UPDATE OF status, vendor_id ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_booking_vendor_performance_change();

-- Trigger function for customer_reviews changes
CREATE OR REPLACE FUNCTION public.fn_on_review_vendor_performance_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_vendor_id UUID;
BEGIN
  IF NEW.rating IS NOT NULL THEN
    -- Resolve vendor_id from booking
    SELECT vendor_id INTO v_vendor_id
    FROM public.bookings
    WHERE id = NEW.booking_id;

    IF v_vendor_id IS NOT NULL THEN
      PERFORM public.evaluate_vendor_performance(v_vendor_id);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_review_vendor_performance ON public.customer_reviews;
CREATE TRIGGER trg_review_vendor_performance
AFTER INSERT OR UPDATE OF rating ON public.customer_reviews
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_review_vendor_performance_change();
