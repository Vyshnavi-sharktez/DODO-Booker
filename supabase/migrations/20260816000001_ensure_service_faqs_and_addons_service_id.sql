-- ============================================================
-- Recovery migration: ensure service_faqs exists and
-- addons.service_id is nullable.
--
-- service_faqs was originally created referencing services(id).
-- If that migration ran after services was already dropped (or
-- was never applied), the table never existed. This migration
-- creates it from scratch with the correct FK to catalog_nodes.
--
-- addons.service_id must be nullable so admins can create addons
-- that are not yet assigned to a specific service.
-- ============================================================

-- ── 1. Ensure service_faqs table exists ───────────────────────────────────────

CREATE TABLE IF NOT EXISTS service_faqs (
  id          UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  service_id  UUID        NOT NULL,
  question    TEXT        NOT NULL,
  answer      TEXT        NOT NULL,
  sort_order  INT         NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_service_faqs_service_id
  ON service_faqs (service_id);

-- ── 2. Fix FK: drop old reference to services, add reference to catalog_nodes ─

DO $$
BEGIN
  -- Drop old FK to services if it survived
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name        = 'service_faqs'
      AND constraint_name   = 'service_faqs_service_id_fkey'
  ) THEN
    ALTER TABLE service_faqs DROP CONSTRAINT service_faqs_service_id_fkey;
  END IF;

  -- Add FK to catalog_nodes if not already present
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name        = 'service_faqs'
      AND constraint_name   = 'service_faqs_service_id_catalog_fkey'
  ) THEN
    ALTER TABLE service_faqs
      ADD CONSTRAINT service_faqs_service_id_catalog_fkey
        FOREIGN KEY (service_id)
        REFERENCES catalog_nodes(id)
        ON DELETE CASCADE;
  END IF;
END;
$$;

-- ── 3. RLS ────────────────────────────────────────────────────────────────────

ALTER TABLE service_faqs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'service_faqs'
      AND policyname = 'service_faqs: public read'
  ) THEN
    CREATE POLICY "service_faqs: public read"
      ON service_faqs FOR SELECT TO anon, authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'service_faqs'
      AND policyname = 'service_faqs: authenticated write'
  ) THEN
    CREATE POLICY "service_faqs: authenticated write"
      ON service_faqs FOR ALL TO authenticated
      USING (true) WITH CHECK (true);
  END IF;
END;
$$;

-- ── 4. Make addons.service_id nullable ────────────────────────────────────────
-- Allows admins to create addons not yet assigned to a specific service.
-- Unassigned addons (service_id IS NULL) are excluded from per-service
-- customer queries (which filter .eq('service_id', nodeId)).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema  = 'public'
      AND table_name    = 'addons'
      AND column_name   = 'service_id'
      AND is_nullable   = 'NO'
  ) THEN
    ALTER TABLE addons ALTER COLUMN service_id DROP NOT NULL;
  END IF;
END;
$$;

-- ── 5. Notify PostgREST to reload its schema cache ────────────────────────────

NOTIFY pgrst, 'reload schema';
