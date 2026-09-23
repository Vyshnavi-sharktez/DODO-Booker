-- ─────────────────────────────────────────────────────────────────────────────
-- Refund Status History
--
-- Immutable audit trail for every status transition on a refund_request.
-- Rows are inserted by RPCs; never updated or deleted.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS refund_status_history (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_request_id UUID        NOT NULL REFERENCES refund_requests(id) ON DELETE CASCADE,

  -- NULL from_status means this is the initial submission entry.
  from_status TEXT,
  to_status   TEXT NOT NULL,

  -- auth.users.id of the actor who caused the transition (NULL for system).
  changed_by      UUID REFERENCES auth.users(id),
  changed_by_type TEXT NOT NULL DEFAULT 'admin'
                    CHECK (changed_by_type IN ('admin', 'customer', 'system')),

  notes    TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_refund_status_history_request_id
  ON refund_status_history (refund_request_id, created_at DESC);

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE refund_status_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_refund_status_history"
  ON refund_status_history;
CREATE POLICY "service_role_all_refund_status_history"
  ON refund_status_history FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "admin_all_refund_status_history" ON refund_status_history;
CREATE POLICY "admin_all_refund_status_history"
  ON refund_status_history FOR ALL
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

-- anon SELECT: future customer app can display the ticket timeline.
DROP POLICY IF EXISTS "anon_select_refund_status_history" ON refund_status_history;
CREATE POLICY "anon_select_refund_status_history"
  ON refund_status_history FOR SELECT
  TO anon
  USING (true);
