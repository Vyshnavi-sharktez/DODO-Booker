-- ── InstaHelp Bookings ────────────────────────────────────────────────────────
--
-- 1. Adds customer-readable SELECT policies to the InstaHelp config tables so
--    the customer app can fetch active modes, durations, and activities without
--    requiring admin privileges.
--
-- 2. Creates instahelp_bookings table that links a standard bookings row to its
--    InstaHelp-specific metadata (mode, duration, pricing snapshot).
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Customer-readable SELECT on config tables (active rows only)

DROP POLICY IF EXISTS "public_read_active_instahelp_modes"       ON public.instahelp_modes;
DROP POLICY IF EXISTS "public_read_active_instahelp_durations"   ON public.instahelp_durations;
DROP POLICY IF EXISTS "public_read_active_instahelp_included"    ON public.instahelp_included_activities;
DROP POLICY IF EXISTS "public_read_active_instahelp_excluded"    ON public.instahelp_excluded_activities;

CREATE POLICY "public_read_active_instahelp_modes"
  ON public.instahelp_modes FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "public_read_active_instahelp_durations"
  ON public.instahelp_durations FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "public_read_active_instahelp_included"
  ON public.instahelp_included_activities FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "public_read_active_instahelp_excluded"
  ON public.instahelp_excluded_activities FOR SELECT
  USING (is_active = TRUE);

-- 2. InstaHelp bookings metadata table

CREATE TABLE IF NOT EXISTS public.instahelp_bookings (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id       UUID        NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  mode_id          UUID        NOT NULL REFERENCES public.instahelp_modes(id),
  duration_id      UUID        NOT NULL REFERENCES public.instahelp_durations(id),
  mode_type        TEXT        NOT NULL CHECK (mode_type IN ('scheduled', 'instant')),
  duration_label   TEXT        NOT NULL,
  duration_minutes INTEGER     NOT NULL,
  base_price       NUMERIC(10,2) NOT NULL,
  final_price      NUMERIC(10,2) NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_instahelp_bookings_booking_id
  ON public.instahelp_bookings(booking_id);

CREATE INDEX IF NOT EXISTS idx_instahelp_bookings_mode_id
  ON public.instahelp_bookings(mode_id);

ALTER TABLE public.instahelp_bookings ENABLE ROW LEVEL SECURITY;

-- Customers can read their own instahelp booking records.
CREATE OR REPLACE FUNCTION public.is_own_booking(p_booking_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.bookings b
    JOIN public.customers c ON c.id = b.customer_id
    WHERE b.id = p_booking_id
      AND c.auth_user_id = auth.uid()
  );
$$;

DROP POLICY IF EXISTS "customer_read_own_instahelp_booking"  ON public.instahelp_bookings;
DROP POLICY IF EXISTS "customer_insert_own_instahelp_booking" ON public.instahelp_bookings;
DROP POLICY IF EXISTS "admin_all_instahelp_bookings"          ON public.instahelp_bookings;

CREATE POLICY "customer_read_own_instahelp_booking"
  ON public.instahelp_bookings FOR SELECT
  USING (public.is_own_booking(booking_id));

CREATE POLICY "customer_insert_own_instahelp_booking"
  ON public.instahelp_bookings FOR INSERT
  WITH CHECK (public.is_own_booking(booking_id));

CREATE POLICY "admin_all_instahelp_bookings"
  ON public.instahelp_bookings FOR ALL
  USING  (public.is_active_admin())
  WITH CHECK (public.is_active_admin());
