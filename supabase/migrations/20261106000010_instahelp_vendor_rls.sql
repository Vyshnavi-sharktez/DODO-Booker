-- Fix instahelp tables so vendors can manage their own mode configuration.
--
-- Problems solved:
--   1. UNIQUE(mode_type) blocks a vendor from inserting mode rows that already
--      exist as admin-global rows (NULL vendor_id).  Replace with two partial
--      unique indexes: one for global rows, one for per-vendor rows.
--
--   2. CHECK (mode_type IN ('scheduled','instant')) rejects 'car_wash'.
--      Extend to include 'car_wash'.
--
--   3. RLS on instahelp_modes / instahelp_durations / instahelp_activities
--      only had admin policies.  Add vendor-scoped policies.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Fix UNIQUE constraint on instahelp_modes.mode_type ────────────────────

ALTER TABLE public.instahelp_modes
  DROP CONSTRAINT IF EXISTS instahelp_modes_mode_type_key;

-- Global (admin) rows: one row per mode_type when vendor_id IS NULL
CREATE UNIQUE INDEX IF NOT EXISTS instahelp_modes_global_mode_uniq
  ON public.instahelp_modes(mode_type)
  WHERE vendor_id IS NULL;

-- Vendor rows: one row per (mode_type, vendor_id) pair
CREATE UNIQUE INDEX IF NOT EXISTS instahelp_modes_vendor_mode_uniq
  ON public.instahelp_modes(mode_type, vendor_id)
  WHERE vendor_id IS NOT NULL;

-- ── 2. Extend CHECK to include car_wash ──────────────────────────────────────

ALTER TABLE public.instahelp_modes
  DROP CONSTRAINT IF EXISTS instahelp_modes_mode_type_check;

ALTER TABLE public.instahelp_modes
  ADD CONSTRAINT instahelp_modes_mode_type_check
  CHECK (mode_type IN ('scheduled', 'instant', 'car_wash'));

-- ── 3. Helper: resolve current auth.uid() → vendor id ────────────────────────

CREATE OR REPLACE FUNCTION public.get_current_vendor_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id
  FROM   public.vendors
  WHERE  auth_user_id = auth.uid()
    AND  is_active    = TRUE
  LIMIT 1;
$$;

-- ── 4. Vendor RLS policies for instahelp_modes ───────────────────────────────

-- Vendors can read all their own mode rows (including inactive)
DROP POLICY IF EXISTS "vendor_read_own_instahelp_modes" ON public.instahelp_modes;
CREATE POLICY "vendor_read_own_instahelp_modes"
  ON public.instahelp_modes FOR SELECT
  USING (vendor_id IS NOT NULL AND vendor_id = public.get_current_vendor_id());

-- Vendors can insert mode rows scoped to themselves
DROP POLICY IF EXISTS "vendor_insert_own_instahelp_modes" ON public.instahelp_modes;
CREATE POLICY "vendor_insert_own_instahelp_modes"
  ON public.instahelp_modes FOR INSERT
  WITH CHECK (vendor_id IS NOT NULL AND vendor_id = public.get_current_vendor_id());

-- Vendors can update their own mode rows
DROP POLICY IF EXISTS "vendor_update_own_instahelp_modes" ON public.instahelp_modes;
CREATE POLICY "vendor_update_own_instahelp_modes"
  ON public.instahelp_modes FOR UPDATE
  USING  (vendor_id IS NOT NULL AND vendor_id = public.get_current_vendor_id())
  WITH CHECK (vendor_id IS NOT NULL AND vendor_id = public.get_current_vendor_id());

-- Vendors can delete their own mode rows
DROP POLICY IF EXISTS "vendor_delete_own_instahelp_modes" ON public.instahelp_modes;
CREATE POLICY "vendor_delete_own_instahelp_modes"
  ON public.instahelp_modes FOR DELETE
  USING (vendor_id IS NOT NULL AND vendor_id = public.get_current_vendor_id());

-- ── 5. Vendor RLS policies for instahelp_durations ───────────────────────────

DROP POLICY IF EXISTS "vendor_all_own_instahelp_durations" ON public.instahelp_durations;
CREATE POLICY "vendor_all_own_instahelp_durations"
  ON public.instahelp_durations FOR ALL
  USING (EXISTS (
    SELECT 1 FROM public.instahelp_modes m
    WHERE  m.id = mode_id
      AND  m.vendor_id IS NOT NULL
      AND  m.vendor_id = public.get_current_vendor_id()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.instahelp_modes m
    WHERE  m.id = mode_id
      AND  m.vendor_id IS NOT NULL
      AND  m.vendor_id = public.get_current_vendor_id()
  ));

-- ── 6. Vendor RLS policies for instahelp_activities ──────────────────────────

DROP POLICY IF EXISTS "vendor_all_own_instahelp_activities" ON public.instahelp_activities;
CREATE POLICY "vendor_all_own_instahelp_activities"
  ON public.instahelp_activities FOR ALL
  USING (EXISTS (
    SELECT 1 FROM public.instahelp_modes m
    WHERE  m.id = mode_id
      AND  m.vendor_id IS NOT NULL
      AND  m.vendor_id = public.get_current_vendor_id()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.instahelp_modes m
    WHERE  m.id = mode_id
      AND  m.vendor_id IS NOT NULL
      AND  m.vendor_id = public.get_current_vendor_id()
  ));
