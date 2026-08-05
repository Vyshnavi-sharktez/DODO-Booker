-- Migration: Update RLS policies for service_warranties, notifications, and booking_images check constraint

-- 1. Update RLS policies on service_warranties to allow select, update, and insert for all roles (anon & authenticated)
DROP POLICY IF EXISTS "Allow anon read service_warranties" ON public.service_warranties;
DROP POLICY IF EXISTS "Allow auth all service_warranties" ON public.service_warranties;
DROP POLICY IF EXISTS "Allow anon all service_warranties" ON public.service_warranties;
DROP POLICY IF EXISTS "Allow all select service_warranties" ON public.service_warranties;
DROP POLICY IF EXISTS "Allow all update service_warranties" ON public.service_warranties;
DROP POLICY IF EXISTS "Allow all insert service_warranties" ON public.service_warranties;

CREATE POLICY "Allow all select service_warranties" ON public.service_warranties
  FOR SELECT USING (true);

CREATE POLICY "Allow all update service_warranties" ON public.service_warranties
  FOR UPDATE USING (true) WITH CHECK (true);

CREATE POLICY "Allow all insert service_warranties" ON public.service_warranties
  FOR INSERT WITH CHECK (true);

-- 2. Update booking_images image_type check constraint to support warranty claim evidence photos
ALTER TABLE public.booking_images
  DROP CONSTRAINT IF EXISTS booking_images_image_type_check;

ALTER TABLE public.booking_images
  ADD CONSTRAINT booking_images_image_type_check
  CHECK (image_type IN ('before', 'after', 'warranty_claim', 'warranty_claim_evidence'));

-- 3. Ensure booking_images RLS policies allow insertion for all roles
DROP POLICY IF EXISTS "anon can insert booking_images" ON public.booking_images;
DROP POLICY IF EXISTS "authenticated can manage booking_images" ON public.booking_images;
DROP POLICY IF EXISTS "Allow all insert booking_images" ON public.booking_images;
DROP POLICY IF EXISTS "Allow all select booking_images" ON public.booking_images;

CREATE POLICY "Allow all insert booking_images" ON public.booking_images
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow all select booking_images" ON public.booking_images
  FOR SELECT USING (true);

CREATE POLICY "Allow all update booking_images" ON public.booking_images
  FOR UPDATE USING (true) WITH CHECK (true);

-- 4. Ensure notifications RLS policies allow insertion for all roles
DROP POLICY IF EXISTS "Allow all insert notifications" ON public.notifications;
CREATE POLICY "Allow all insert notifications" ON public.notifications
  FOR INSERT WITH CHECK (true);
