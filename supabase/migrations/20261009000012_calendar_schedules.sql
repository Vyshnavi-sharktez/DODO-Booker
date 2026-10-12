-- calendar_schedules: date-specific slot overrides for normal scheduling
-- service_id NULL = global override; non-null = per-service override
-- Priority in slot resolution: service calendar > global calendar > normal schedule

CREATE TABLE IF NOT EXISTS calendar_schedules (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id             UUID        REFERENCES catalog_nodes(id) ON DELETE CASCADE,
  schedule_date          DATE        NOT NULL,
  slots                  TEXT[]      NOT NULL DEFAULT '{}',
  max_bookings_per_slot  INT         NOT NULL DEFAULT 5,
  is_enabled             BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One global override per date (service_id IS NULL)
CREATE UNIQUE INDEX IF NOT EXISTS calendar_schedules_global_date_uniq
  ON calendar_schedules (schedule_date)
  WHERE service_id IS NULL;

-- One service override per (service_id, date)
CREATE UNIQUE INDEX IF NOT EXISTS calendar_schedules_service_date_uniq
  ON calendar_schedules (service_id, schedule_date)
  WHERE service_id IS NOT NULL;

ALTER TABLE calendar_schedules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "calendar_schedules_admin_all"
  ON calendar_schedules FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- Customer/vendor apps read via anon key
CREATE POLICY "calendar_schedules_anon_read"
  ON calendar_schedules FOR SELECT TO anon
  USING (true);
