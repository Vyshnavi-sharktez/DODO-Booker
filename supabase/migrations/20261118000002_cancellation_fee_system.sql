-- ─────────────────────────────────────────────────────────────────────────────
-- Dynamic Customer Cancellation Fee System — DB schema
--
-- Adds:
--   1. bookings columns: cancellation_fee_amount, cancellation_fee_collected,
--      cancellation_remarks
--   2. cancellation_policies table (one row per policy_type, seeded disabled)
--   3. cancellation_policy_slabs table (admin-configured time/fee ranges)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Bookings columns ──────────────────────────────────────────────────────────

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS cancellation_fee_amount    NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cancellation_fee_collected BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS cancellation_remarks       TEXT;

-- ── cancellation_policies ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS cancellation_policies (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_type TEXT        NOT NULL UNIQUE
                          CHECK (policy_type IN ('before_assignment', 'after_assignment')),
  is_enabled  BOOLEAN     NOT NULL DEFAULT FALSE,
  label       TEXT        NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE cancellation_policies ENABLE ROW LEVEL SECURITY;

-- Public read (customers/vendors see fee rules via SECURITY DEFINER RPCs);
-- no direct DML from client.
CREATE POLICY "cancellation_policies_select"
  ON cancellation_policies FOR SELECT TO authenticated USING (TRUE);

-- ── cancellation_policy_slabs ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS cancellation_policy_slabs (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_id    UUID        NOT NULL REFERENCES cancellation_policies(id) ON DELETE CASCADE,
  from_minutes INTEGER     NOT NULL CHECK (from_minutes >= 0),
  to_minutes   INTEGER     CHECK (to_minutes IS NULL OR to_minutes > from_minutes),
  fee_amount   NUMERIC(12,2) NOT NULL CHECK (fee_amount >= 0),
  label        TEXT,
  sort_order   INTEGER     NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE cancellation_policy_slabs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cancellation_policy_slabs_select"
  ON cancellation_policy_slabs FOR SELECT TO authenticated USING (TRUE);

-- ── Seed the two canonical policy rows ───────────────────────────────────────

INSERT INTO cancellation_policies (policy_type, is_enabled, label, description)
VALUES
  ('before_assignment', FALSE,
   'Before Assignment',
   'Applies when the customer cancels before a vendor has been assigned. Time measured from when the booking was placed.'),
  ('after_assignment', FALSE,
   'After Assignment',
   'Applies when the customer cancels after a vendor has been assigned. Time measured as remaining minutes until the scheduled service.')
ON CONFLICT (policy_type) DO NOTHING;
