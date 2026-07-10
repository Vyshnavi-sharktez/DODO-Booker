-- Global scheduling: singleton table for an admin-wide slot configuration.
-- Individual services opt in via service_scheduling.use_global_schedule.
-- Structure mirrors service_scheduling for consistent Dart parsing.

CREATE TABLE IF NOT EXISTS global_scheduling (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled            BOOLEAN     NOT NULL DEFAULT false,
  working_days          INTEGER[]   NOT NULL DEFAULT ARRAY[1,2,3,4,5],
  max_bookings_per_slot INTEGER     NOT NULL DEFAULT 5,
  slots                 TEXT[]      NOT NULL DEFAULT ARRAY[]::TEXT[],
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Opt-in flag per service. Default false keeps all existing services unchanged.
ALTER TABLE service_scheduling
  ADD COLUMN IF NOT EXISTS use_global_schedule BOOLEAN NOT NULL DEFAULT false;

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE global_scheduling ENABLE ROW LEVEL SECURITY;

-- Admin (authenticated) has full CRUD — matches service_scheduling pattern.
CREATE POLICY "authenticated_all" ON global_scheduling
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Customer app may use the anon role to read slots before sign-in.
CREATE POLICY "anon_read" ON global_scheduling
  FOR SELECT TO anon USING (true);

-- ── Seed row ──────────────────────────────────────────────────────────────────

-- Guarantee exactly one row so the admin page always issues UPDATE, not INSERT.
-- Mirrors the loyalty_settings seed pattern.
INSERT INTO global_scheduling (is_enabled, working_days, max_bookings_per_slot, slots)
SELECT false, ARRAY[1,2,3,4,5], 5, ARRAY[]::TEXT[]
WHERE NOT EXISTS (SELECT 1 FROM global_scheduling);
