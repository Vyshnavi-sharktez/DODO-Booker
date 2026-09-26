-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — Tables, Indexes, RLS
--
-- Implements Phase 1: Customer ↔ Admin real-time support chat.
-- One active conversation per customer. Text messages only (V1).
-- Customer access is gated entirely behind SECURITY DEFINER RPCs (migration
-- 20260926000002). Direct anon access to these tables is intentionally blocked.
--
-- Status semantics:
--   open             – conversation exists; no unread customer message yet
--   pending_admin    – customer sent a message; admin has not read it
--   pending_customer – admin replied; customer has not read it
--   closed           – admin explicitly closed the conversation
--
-- Unread counters:
--   unread_admin_count    – customer messages not yet read by admin
--   unread_customer_count – admin messages not yet read by customer
--   Both are maintained atomically by triggers (migration 20260926000003).
--
-- Per-message read flags:
--   is_read_by_admin    – set true immediately for admin-sent messages (own)
--   is_read_by_customer – set true immediately for customer-sent messages (own)
--   Both are set by the BEFORE INSERT trigger; not set by this migration.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── support_conversations ─────────────────────────────────────────────────────
-- One row per customer. Holds conversation state and denormalised counters.
-- Phase 2 note: add vendor_id UUID NULL REFERENCES vendors(id) + CHECK constraint.

CREATE TABLE IF NOT EXISTS support_conversations (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id           UUID        NOT NULL REFERENCES customers(id) ON DELETE CASCADE,

  status                TEXT        NOT NULL DEFAULT 'open'
                          CHECK (status IN ('open', 'closed', 'pending_admin', 'pending_customer')),

  last_message_at       TIMESTAMPTZ,
  last_message_preview  TEXT,                  -- first 120 chars for admin inbox list

  -- Denormalised; maintained atomically by triggers.
  unread_admin_count    INT         NOT NULL DEFAULT 0 CHECK (unread_admin_count >= 0),
  unread_customer_count INT         NOT NULL DEFAULT 0 CHECK (unread_customer_count >= 0),

  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── support_messages ──────────────────────────────────────────────────────────
-- One row per message. sender_id is customers.id or admin_users.id depending on
-- sender_type — no FK constraint because both reference different tables.

CREATE TABLE IF NOT EXISTS support_messages (
  id                  UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id     UUID    NOT NULL REFERENCES support_conversations(id) ON DELETE CASCADE,

  sender_type         TEXT    NOT NULL CHECK (sender_type IN ('customer', 'admin')),
  sender_id           UUID    NOT NULL,   -- customers.id or admin_users.id

  message             TEXT    NOT NULL CHECK (length(trim(message)) > 0),

  -- Set true immediately for the sender's own messages by BEFORE INSERT trigger.
  is_read_by_admin    BOOLEAN NOT NULL DEFAULT false,
  is_read_by_customer BOOLEAN NOT NULL DEFAULT false,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── support_reminder_logs ────────────────────────────────────────────────────
-- Records every reminder notification sent for a conversation.
-- Cleared on conversation close/reopen by trigger (migration 20260926000003)
-- so each open episode starts with a fresh reminder counter.

CREATE TABLE IF NOT EXISTS support_reminder_logs (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id  UUID        NOT NULL REFERENCES support_conversations(id) ON DELETE CASCADE,
  sent_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Indexes ───────────────────────────────────────────────────────────────────

-- Primary customer lookup (get_or_create, get_conversation RPCs)
CREATE INDEX IF NOT EXISTS idx_support_conv_customer_id
  ON support_conversations (customer_id);

-- Admin inbox: sort by most recent activity
CREATE INDEX IF NOT EXISTS idx_support_conv_last_message_at
  ON support_conversations (last_message_at DESC NULLS LAST);

-- Filter open/pending conversations (reminder function, admin inbox filter)
CREATE INDEX IF NOT EXISTS idx_support_conv_status
  ON support_conversations (status);

-- Primary message thread read path
CREATE INDEX IF NOT EXISTS idx_support_msg_conv_created
  ON support_messages (conversation_id, created_at ASC);

-- Partial index for unread admin messages (reminder function query)
CREATE INDEX IF NOT EXISTS idx_support_msg_unread_admin
  ON support_messages (conversation_id, created_at)
  WHERE is_read_by_admin = false;

-- Reminder log lookups (eligibility check)
CREATE INDEX IF NOT EXISTS idx_support_reminder_conv_id
  ON support_reminder_logs (conversation_id);

CREATE INDEX IF NOT EXISTS idx_support_reminder_sent_at
  ON support_reminder_logs (sent_at DESC);

-- ── RLS: support_conversations ───────────────────────────────────────────────

ALTER TABLE support_conversations ENABLE ROW LEVEL SECURITY;

-- service_role bypasses RLS for triggers and internal operations.
DROP POLICY IF EXISTS "service_role_all_support_conversations" ON support_conversations;
CREATE POLICY "service_role_all_support_conversations"
  ON support_conversations FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

-- Active admins: full read access + ability to update status/counters.
-- INSERT is handled by the SECURITY DEFINER get_or_create RPC, not direct admin writes.
DROP POLICY IF EXISTS "admin_select_support_conversations" ON support_conversations;
CREATE POLICY "admin_select_support_conversations"
  ON support_conversations FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

DROP POLICY IF EXISTS "admin_update_support_conversations" ON support_conversations;
CREATE POLICY "admin_update_support_conversations"
  ON support_conversations FOR UPDATE
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

-- anon: no direct access — all customer reads/writes go through SECURITY DEFINER RPCs.

-- ── RLS: support_messages ─────────────────────────────────────────────────────

ALTER TABLE support_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_support_messages" ON support_messages;
CREATE POLICY "service_role_all_support_messages"
  ON support_messages FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

-- Active admins: read all messages.
DROP POLICY IF EXISTS "admin_select_support_messages" ON support_messages;
CREATE POLICY "admin_select_support_messages"
  ON support_messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

-- Active admins: insert their own replies only.
DROP POLICY IF EXISTS "admin_insert_support_messages" ON support_messages;
CREATE POLICY "admin_insert_support_messages"
  ON support_messages FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_type = 'admin'
    AND EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

-- Active admins: update read flags only (is_read_by_admin).
DROP POLICY IF EXISTS "admin_update_support_messages" ON support_messages;
CREATE POLICY "admin_update_support_messages"
  ON support_messages FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

-- anon: no direct access — customer reads/writes go through SECURITY DEFINER RPCs.

-- ── RLS: support_reminder_logs ────────────────────────────────────────────────

ALTER TABLE support_reminder_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_support_reminder_logs" ON support_reminder_logs;
CREATE POLICY "service_role_all_support_reminder_logs"
  ON support_reminder_logs FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

-- Active admins: read-only (for monitoring/diagnostics).
DROP POLICY IF EXISTS "admin_select_support_reminder_logs" ON support_reminder_logs;
CREATE POLICY "admin_select_support_reminder_logs"
  ON support_reminder_logs FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

-- anon: no access.
