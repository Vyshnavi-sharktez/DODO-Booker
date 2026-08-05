-- Migration: Create service_warranties table and automatic warranty generation engine

-- 1. Create service_warranties table
CREATE TABLE IF NOT EXISTS public.service_warranties (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL UNIQUE REFERENCES public.bookings(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL,
  vendor_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL,
  warranty_days INT NOT NULL DEFAULT 30,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Expired', 'Claimed')),
  claimed_at TIMESTAMPTZ,
  rework_booking_id UUID REFERENCES public.bookings(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Indexes
CREATE INDEX IF NOT EXISTS idx_service_warranties_booking_id ON public.service_warranties(booking_id);
CREATE INDEX IF NOT EXISTS idx_service_warranties_customer_id ON public.service_warranties(customer_id);
CREATE INDEX IF NOT EXISTS idx_service_warranties_vendor_id ON public.service_warranties(vendor_id);
CREATE INDEX IF NOT EXISTS idx_service_warranties_status ON public.service_warranties(status);

-- 3. Row Level Security
ALTER TABLE public.service_warranties ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow anon read service_warranties" ON public.service_warranties;
CREATE POLICY "Allow anon read service_warranties" ON public.service_warranties
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow auth all service_warranties" ON public.service_warranties;
CREATE POLICY "Allow auth all service_warranties" ON public.service_warranties
  FOR ALL USING (auth.role() = 'authenticated');

-- Realtime setup
ALTER PUBLICATION supabase_realtime ADD TABLE public.service_warranties;

-- 4. Default Setting for Warranty Days
INSERT INTO public.settings (setting_key, setting_value)
VALUES ('default_warranty_days', '30')
ON CONFLICT (setting_key) DO NOTHING;

-- 5. Trigger Function: Automatically generate warranty on booking completion
CREATE OR REPLACE FUNCTION public.fn_auto_generate_service_warranty()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_warranty_days INT := 30;
  v_expires_at TIMESTAMPTZ;
BEGIN
  -- Trigger when booking transitions to completed
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    -- Prevent duplicate warranty creation for the same booking
    IF NOT EXISTS (SELECT 1 FROM public.service_warranties WHERE booking_id = NEW.id) THEN
      -- Read default warranty duration from settings
      SELECT COALESCE(NULLIF(TRIM(setting_value), '')::INT, 30) INTO v_warranty_days
      FROM public.settings
      WHERE setting_key = 'default_warranty_days';

      IF v_warranty_days <= 0 THEN
        v_warranty_days := 30;
      END IF;

      v_expires_at := now() + (v_warranty_days || ' days')::INTERVAL;

      INSERT INTO public.service_warranties (
        booking_id,
        customer_id,
        vendor_id,
        warranty_days,
        issued_at,
        expires_at,
        status,
        created_at,
        updated_at
      ) VALUES (
        NEW.id,
        NEW.customer_id,
        NEW.vendor_id,
        v_warranty_days,
        now(),
        v_expires_at,
        'Active',
        now(),
        now()
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_generate_service_warranty ON public.bookings;
CREATE TRIGGER trg_auto_generate_service_warranty
AFTER INSERT OR UPDATE OF status ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.fn_auto_generate_service_warranty();

-- 6. Stored Procedure: Process and mark expired service warranties
CREATE OR REPLACE FUNCTION public.process_expired_service_warranties()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INT;
BEGIN
  UPDATE public.service_warranties
  SET status = 'Expired', updated_at = now()
  WHERE status = 'Active' AND expires_at < now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- 7. Backfill active warranties for existing completed bookings missing a warranty record
DO $$
DECLARE
  v_rec RECORD;
  v_warranty_days INT := 30;
  v_expires_at TIMESTAMPTZ;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(setting_value), '')::INT, 30) INTO v_warranty_days
  FROM public.settings
  WHERE setting_key = 'default_warranty_days';

  IF v_warranty_days <= 0 THEN
    v_warranty_days := 30;
  END IF;

  FOR v_rec IN
    SELECT b.id AS booking_id, b.customer_id, b.vendor_id, COALESCE(b.updated_at, b.created_at) AS completed_at
    FROM public.bookings b
    LEFT JOIN public.service_warranties w ON b.id = w.booking_id
    WHERE b.status = 'completed' AND w.id IS NULL
  LOOP
    v_expires_at := v_rec.completed_at + (v_warranty_days || ' days')::INTERVAL;

    INSERT INTO public.service_warranties (
      booking_id,
      customer_id,
      vendor_id,
      warranty_days,
      issued_at,
      expires_at,
      status,
      created_at,
      updated_at
    ) VALUES (
      v_rec.booking_id,
      v_rec.customer_id,
      v_rec.vendor_id,
      v_warranty_days,
      v_rec.completed_at,
      v_expires_at,
      CASE WHEN v_expires_at < now() THEN 'Expired' ELSE 'Active' END,
      v_rec.completed_at,
      now()
    );
  END LOOP;
END;
$$;
