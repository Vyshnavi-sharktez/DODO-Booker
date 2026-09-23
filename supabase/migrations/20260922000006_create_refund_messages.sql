-- ─────────────────────────────────────────────────────────────────────────────
-- Refund Messages
--
-- Threaded communication channel attached to a refund ticket.
-- Supports customer↔admin messaging plus internal admin-only notes.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS refund_messages (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_request_id UUID        NOT NULL REFERENCES refund_requests(id) ON DELETE CASCADE,

  sender_type TEXT NOT NULL CHECK (sender_type IN ('customer', 'admin')),

  -- customer_id (customers.id) when sender_type = 'customer'.
  -- admin_users.id when sender_type = 'admin'.
  sender_id   UUID NOT NULL,

  message     TEXT NOT NULL CHECK (length(trim(message)) > 0),

  -- Optional single attachment.
  attachment_url TEXT,

  -- When true the message is visible to admins only (not shown to customer).
  is_internal BOOLEAN NOT NULL DEFAULT false,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_refund_messages_request_id
  ON refund_messages (refund_request_id, created_at);

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE refund_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_refund_messages" ON refund_messages;
CREATE POLICY "service_role_all_refund_messages"
  ON refund_messages FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "admin_all_refund_messages" ON refund_messages;
CREATE POLICY "admin_all_refund_messages"
  ON refund_messages FOR ALL
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

-- anon SELECT: future customer app — only non-internal messages.
DROP POLICY IF EXISTS "anon_select_public_refund_messages" ON refund_messages;
CREATE POLICY "anon_select_public_refund_messages"
  ON refund_messages FOR SELECT
  TO anon
  USING (is_internal = FALSE);

-- anon INSERT: future customer app ticket replies.
-- NOT created yet; customer app UI is out of scope for Phase 1.
