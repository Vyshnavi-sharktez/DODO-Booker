-- ─────────────────────────────────────────────────────────────────────────────
-- Refund Policies
--
-- Admin-configurable rules that govern refund eligibility and limits.
-- Policies are scoped: global → catalog_node → service (higher specificity wins).
-- Backend RPCs evaluate these at runtime; business rules MUST NOT be hardcoded
-- in Flutter or application code.
--
-- Financial safety invariants are enforced in the RPC layer regardless of
-- policy configuration.  A policy can never allow refunding more than the
-- verified collected amount.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS refund_policies (
  id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,

  -- Eligibility: which booking states and payment methods are covered.
  eligible_booking_statuses TEXT[]       NOT NULL DEFAULT ARRAY['completed','cancelled'],
  eligible_payment_methods  TEXT[]       NOT NULL DEFAULT ARRAY['online','cash','cod'],

  -- Time window after the booking's service_date (NULL = no time limit enforced).
  max_request_window_hours  INTEGER      CHECK (max_request_window_hours > 0),

  -- Refund amount rules.
  allow_full_refund         BOOLEAN      NOT NULL DEFAULT true,
  allow_partial_refund      BOOLEAN      NOT NULL DEFAULT true,
  -- Maximum percentage of the collected amount that may be refunded (0–100).
  max_refund_percentage     NUMERIC(5,2) NOT NULL DEFAULT 100.00
                              CHECK (max_refund_percentage BETWEEN 0 AND 100),

  -- Evidence requirements.
  requires_evidence         BOOLEAN      NOT NULL DEFAULT false,
  min_evidence_count        SMALLINT     NOT NULL DEFAULT 0
                              CHECK (min_evidence_count >= 0),

  -- Scope: 'global' covers all bookings; others narrow to a catalog node or service.
  applies_to    TEXT    NOT NULL DEFAULT 'global'
                  CHECK (applies_to IN ('global', 'catalog_node', 'service')),
  applies_to_id UUID,  -- NULL for 'global'; references catalog_nodes or services

  -- Higher priority wins when multiple active policies match the same booking.
  priority   INTEGER     NOT NULL DEFAULT 0,
  is_active  BOOLEAN     NOT NULL DEFAULT true,

  created_by UUID        REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_refund_policies_scope
  ON refund_policies (applies_to, applies_to_id, is_active, priority DESC);

-- ── updated_at trigger ────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_refund_policies_updated_at ON refund_policies;
CREATE TRIGGER trg_refund_policies_updated_at
  BEFORE UPDATE ON refund_policies
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_subscription();

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE refund_policies ENABLE ROW LEVEL SECURITY;

-- Admins with refund.policy.manage: full CRUD.
-- Checked at application level; RLS enforces admin-only access.
DROP POLICY IF EXISTS "admin_all_refund_policies" ON refund_policies;
CREATE POLICY "admin_all_refund_policies"
  ON refund_policies FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

-- anon SELECT (active policies only): future customer eligibility checks.
DROP POLICY IF EXISTS "anon_select_active_refund_policies" ON refund_policies;
CREATE POLICY "anon_select_active_refund_policies"
  ON refund_policies FOR SELECT
  TO anon
  USING (is_active = TRUE);

-- ── Default global policy ─────────────────────────────────────────────────────
-- Safe starter configuration.  Admin can update or deactivate at any time.

INSERT INTO refund_policies (
  name,
  description,
  eligible_booking_statuses,
  eligible_payment_methods,
  max_request_window_hours,
  allow_full_refund,
  allow_partial_refund,
  max_refund_percentage,
  requires_evidence,
  min_evidence_count,
  applies_to,
  priority,
  is_active
) VALUES (
  'Default Global Policy',
  'Baseline refund policy covering all bookings. Admin should review and adjust.',
  ARRAY['completed', 'cancelled'],
  ARRAY['online', 'cash', 'cod'],
  720,  -- 30 days
  true,
  true,
  100.00,
  false,
  0,
  'global',
  0,
  true
) ON CONFLICT DO NOTHING;
