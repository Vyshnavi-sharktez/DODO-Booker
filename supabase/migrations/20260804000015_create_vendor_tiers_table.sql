-- ── Vendor Tiers Foundation ──────────────────────────────────────────────────
--
-- Stores dynamic vendor tier definitions for priority dispatch and tier configuration.
-- Priority determines dispatch rank (lower integer = higher priority).

CREATE TABLE IF NOT EXISTS public.vendor_tiers (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT        NOT NULL,
  description   TEXT,
  priority      INT         NOT NULL DEFAULT 1,
  badge_color   TEXT        NOT NULL DEFAULT '#4285F4',
  badge_icon    TEXT,
  is_active     BOOLEAN     NOT NULL DEFAULT true,
  created_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for fast ordering by priority
CREATE INDEX IF NOT EXISTS idx_vendor_tiers_priority ON public.vendor_tiers (priority ASC, created_at ASC);

-- Row Level Security
ALTER TABLE public.vendor_tiers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "vt_anon_read" ON public.vendor_tiers FOR SELECT TO anon USING (true);
CREATE POLICY "vt_auth_all"  ON public.vendor_tiers FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Realtime Publication
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
        FROM pg_publication_tables
       WHERE pubname   = 'supabase_realtime'
         AND tablename = 'vendor_tiers'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.vendor_tiers;
    END IF;
  END IF;
END;
$$;
