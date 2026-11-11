-- Merge instahelp_included_activities + instahelp_excluded_activities into one
-- unified instahelp_activities table.
--
-- Each row is now an "activity group" (e.g. Kitchen) with both included_items
-- and excluded_items as independent JSONB lists.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Create unified table
CREATE TABLE IF NOT EXISTS public.instahelp_activities (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  mode_id          UUID          NOT NULL REFERENCES public.instahelp_modes(id) ON DELETE CASCADE,
  title            TEXT          NOT NULL,
  included_items   JSONB         NOT NULL DEFAULT '[]'::jsonb,
  excluded_items   JSONB         NOT NULL DEFAULT '[]'::jsonb,
  is_active        BOOLEAN       NOT NULL DEFAULT TRUE,
  sort_order       INTEGER       NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- 2. Migrate existing data from split tables (safe — works regardless of which
--    prior migrations were applied, using runtime column-existence checks)
DO $$
DECLARE
  has_items_col boolean;
BEGIN
  -- Migrate included activities
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'instahelp_included_activities'
  ) THEN
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name   = 'instahelp_included_activities'
        AND column_name  = 'items'
    ) INTO has_items_col;

    IF has_items_col THEN
      INSERT INTO public.instahelp_activities
        (mode_id, title, included_items, is_active, sort_order, created_at)
      SELECT mode_id, title, COALESCE(items, '[]'::jsonb), is_active, sort_order, created_at
      FROM   public.instahelp_included_activities
      ON CONFLICT DO NOTHING;
    ELSE
      INSERT INTO public.instahelp_activities
        (mode_id, title, included_items, is_active, sort_order, created_at)
      SELECT mode_id, title, '[]'::jsonb, is_active, sort_order, created_at
      FROM   public.instahelp_included_activities
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- Merge excluded activities: match by (mode_id, lower(title)), insert orphans
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'instahelp_excluded_activities'
  ) THEN
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name   = 'instahelp_excluded_activities'
        AND column_name  = 'items'
    ) INTO has_items_col;

    IF has_items_col THEN
      -- Update existing rows where title matches
      UPDATE public.instahelp_activities a
      SET    excluded_items = COALESCE(e.items, '[]'::jsonb)
      FROM   public.instahelp_excluded_activities e
      WHERE  a.mode_id = e.mode_id AND LOWER(a.title) = LOWER(e.title);

      -- Insert excluded-only groups (no matching included title)
      INSERT INTO public.instahelp_activities
        (mode_id, title, excluded_items, is_active, sort_order, created_at)
      SELECT e.mode_id, e.title, COALESCE(e.items, '[]'::jsonb),
             e.is_active, e.sort_order, e.created_at
      FROM   public.instahelp_excluded_activities e
      WHERE  NOT EXISTS (
        SELECT 1 FROM public.instahelp_activities a
        WHERE  a.mode_id = e.mode_id AND LOWER(a.title) = LOWER(e.title)
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;
END $$;

-- 3. Index
CREATE INDEX IF NOT EXISTS idx_instahelp_activities_mode_id
  ON public.instahelp_activities(mode_id);

-- 4. updated_at trigger
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'instahelp_activities_set_updated_at'
  ) THEN
    CREATE TRIGGER instahelp_activities_set_updated_at
      BEFORE UPDATE ON public.instahelp_activities
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

-- 5. RLS
ALTER TABLE public.instahelp_activities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_all_instahelp_activities"    ON public.instahelp_activities;
DROP POLICY IF EXISTS "read_active_instahelp_activities"  ON public.instahelp_activities;

-- Admins: full access
CREATE POLICY "admin_all_instahelp_activities"
  ON public.instahelp_activities FOR ALL
  USING  (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- Authenticated users (customers / vendors): read active rows only
CREATE POLICY "read_active_instahelp_activities"
  ON public.instahelp_activities FOR SELECT
  USING (is_active = TRUE AND auth.uid() IS NOT NULL);

-- 6. Drop the now-superseded split tables
DROP TABLE IF EXISTS public.instahelp_included_activities;
DROP TABLE IF EXISTS public.instahelp_excluded_activities;
