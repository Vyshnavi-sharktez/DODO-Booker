-- ── InstaHelp Configuration ───────────────────────────────────────────────────
--
-- Creates backend tables for the InstaHelp admin configuration module:
--
--   instahelp_modes               — two canonical rows: 'scheduled', 'instant'
--   instahelp_durations           — admin-defined duration options with pricing
--   instahelp_included_activities — activities shown as "what's included"
--   instahelp_excluded_activities — activities shown as "what's excluded"
--
-- Scheduled and Instant are independent configurations sharing this schema.
-- Both mode rows are seeded at the end of this migration.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Modes
CREATE TABLE IF NOT EXISTS public.instahelp_modes (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  mode_type   TEXT        NOT NULL UNIQUE CHECK (mode_type IN ('scheduled', 'instant')),
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Duration options per mode
CREATE TABLE IF NOT EXISTS public.instahelp_durations (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  mode_id          UUID        NOT NULL REFERENCES public.instahelp_modes(id) ON DELETE CASCADE,
  label            TEXT        NOT NULL,
  duration_minutes INTEGER     NOT NULL CHECK (duration_minutes > 0),
  price            NUMERIC(10,2) NOT NULL CHECK (price >= 0),
  discount_type    TEXT        NOT NULL DEFAULT 'none'
                                 CHECK (discount_type IN ('none', 'percentage', 'fixed')),
  discount_value   NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (discount_value >= 0),
  is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order       INTEGER     NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT instahelp_durations_pct_max
    CHECK (discount_type <> 'percentage' OR discount_value <= 100)
);

-- 3. Included activities
CREATE TABLE IF NOT EXISTS public.instahelp_included_activities (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  mode_id     UUID        NOT NULL REFERENCES public.instahelp_modes(id) ON DELETE CASCADE,
  title       TEXT        NOT NULL,
  description TEXT,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Excluded activities
CREATE TABLE IF NOT EXISTS public.instahelp_excluded_activities (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  mode_id     UUID        NOT NULL REFERENCES public.instahelp_modes(id) ON DELETE CASCADE,
  title       TEXT        NOT NULL,
  description TEXT,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Indexes
CREATE INDEX IF NOT EXISTS idx_instahelp_durations_mode_id
  ON public.instahelp_durations(mode_id);

CREATE INDEX IF NOT EXISTS idx_instahelp_included_mode_id
  ON public.instahelp_included_activities(mode_id);

CREATE INDEX IF NOT EXISTS idx_instahelp_excluded_mode_id
  ON public.instahelp_excluded_activities(mode_id);

-- 6. updated_at triggers
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'instahelp_modes_set_updated_at') THEN
    CREATE TRIGGER instahelp_modes_set_updated_at
      BEFORE UPDATE ON public.instahelp_modes
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'instahelp_durations_set_updated_at') THEN
    CREATE TRIGGER instahelp_durations_set_updated_at
      BEFORE UPDATE ON public.instahelp_durations
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'instahelp_included_set_updated_at') THEN
    CREATE TRIGGER instahelp_included_set_updated_at
      BEFORE UPDATE ON public.instahelp_included_activities
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'instahelp_excluded_set_updated_at') THEN
    CREATE TRIGGER instahelp_excluded_set_updated_at
      BEFORE UPDATE ON public.instahelp_excluded_activities
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

-- 7. RLS
ALTER TABLE public.instahelp_modes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instahelp_durations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instahelp_included_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instahelp_excluded_activities ENABLE ROW LEVEL SECURITY;

-- Active-admin helper (safe to re-create; other migrations may already have it)
CREATE OR REPLACE FUNCTION public.is_active_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE auth_user_id = auth.uid() AND is_active = TRUE
  );
$$;

DROP POLICY IF EXISTS "admin_all_instahelp_modes"       ON public.instahelp_modes;
DROP POLICY IF EXISTS "admin_all_instahelp_durations"   ON public.instahelp_durations;
DROP POLICY IF EXISTS "admin_all_instahelp_included"    ON public.instahelp_included_activities;
DROP POLICY IF EXISTS "admin_all_instahelp_excluded"    ON public.instahelp_excluded_activities;

CREATE POLICY "admin_all_instahelp_modes"
  ON public.instahelp_modes FOR ALL
  USING  (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

CREATE POLICY "admin_all_instahelp_durations"
  ON public.instahelp_durations FOR ALL
  USING  (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

CREATE POLICY "admin_all_instahelp_included"
  ON public.instahelp_included_activities FOR ALL
  USING  (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

CREATE POLICY "admin_all_instahelp_excluded"
  ON public.instahelp_excluded_activities FOR ALL
  USING  (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- 8. Seed both modes
INSERT INTO public.instahelp_modes (mode_type, is_active)
VALUES
  ('scheduled', TRUE),
  ('instant',   TRUE)
ON CONFLICT (mode_type) DO NOTHING;
