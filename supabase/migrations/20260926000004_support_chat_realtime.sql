-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — Supabase Realtime Publication
--
-- Adds support_conversations and support_messages to the supabase_realtime
-- publication so that:
--   • Customer app: can subscribe to new messages in their conversation
--     (channel per conversation_id, INSERT events on support_messages).
--   • Customer app: can receive conversation status updates
--     (UPDATE events on support_conversations for the 'closed' banner).
--   • Admin panel: can receive new conversation and message events in real time
--     for the support inbox (added to the existing dodo-admin-sync channel).
--
-- Idempotent: wrapped in DO blocks that check pg_publication_tables before
-- adding, so re-running this migration is safe.
--
-- Existing publication tables are unchanged (notifications, bookings, etc.).
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_publication_tables
     WHERE pubname   = 'supabase_realtime'
       AND tablename = 'support_conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE support_conversations;
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_publication_tables
     WHERE pubname   = 'supabase_realtime'
       AND tablename = 'support_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE support_messages;
  END IF;
END;
$$;
