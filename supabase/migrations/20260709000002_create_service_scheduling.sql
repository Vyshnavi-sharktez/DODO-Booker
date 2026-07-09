-- Dynamic service-wise scheduling
-- Stores per-service slot configuration. service_id maps to services(id).

CREATE TABLE IF NOT EXISTS service_scheduling (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id            UUID        NOT NULL UNIQUE,
  is_enabled            BOOLEAN     NOT NULL DEFAULT true,
  working_days          INTEGER[]   NOT NULL DEFAULT ARRAY[1,2,3,4,5],  -- 0=Sun … 6=Sat
  start_time            TIME        NOT NULL DEFAULT '08:00:00',
  end_time              TIME        NOT NULL DEFAULT '20:00:00',
  slot_interval_minutes INTEGER     NOT NULL DEFAULT 60,
  max_bookings_per_slot INTEGER     NOT NULL DEFAULT 5,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE service_scheduling ENABLE ROW LEVEL SECURITY;

-- Admin (authenticated) has full access
CREATE POLICY "authenticated_all" ON service_scheduling
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Customer app (anon) can read scheduling to generate available slots
CREATE POLICY "anon_read" ON service_scheduling
  FOR SELECT TO anon USING (true);
