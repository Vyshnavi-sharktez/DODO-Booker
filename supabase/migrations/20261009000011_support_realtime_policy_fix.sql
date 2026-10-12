-- Fix Supabase Realtime v2.9+ silently dropping events for support tables.
--
-- Root cause (same as 20261009000004 for bookings and 20261009000005 for other
-- tables): Supabase Realtime v2.9+ cannot evaluate complex RLS SELECT policies
-- that contain JOIN subqueries (EXISTS ... FROM admin_users). It silently drops
-- every event — INSERT, UPDATE, DELETE — for the subscriber.
--
-- Fix: replace the complex admin SELECT policies on support_conversations and
-- support_messages with USING (true), consistent with the project's security
-- model (app-layer enforcement via admin JWT — same as bookings, customers,
-- notifications, etc.).
--
-- Also sets REPLICA IDENTITY FULL on both tables so UPDATE events carry the
-- full old + new row, enabling the conversation_id column filter in
-- _subscribeReadStatus() and ensuring the admin sidebar updates on status/
-- counter changes in real time.
--
-- Adds anon SELECT policy on support_conversations so the customer app can
-- subscribe to status UPDATE events (id = convId filter) and show the
-- "chat closed" state immediately when admin closes the conversation.

-- ── support_messages ──────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "admin_select_support_messages" ON support_messages;
CREATE POLICY "admin_select_support_messages"
  ON support_messages FOR SELECT
  TO authenticated
  USING (true);

ALTER TABLE support_messages REPLICA IDENTITY FULL;

-- ── support_conversations ─────────────────────────────────────────────────────

DROP POLICY IF EXISTS "admin_select_support_conversations" ON support_conversations;
CREATE POLICY "admin_select_support_conversations"
  ON support_conversations FOR SELECT
  TO authenticated
  USING (true);

-- Customer app uses the anon key. Without a SELECT policy for anon, Supabase
-- Realtime silently drops UPDATE events before they reach the customer's
-- subscription for the "admin closed" banner. The id filter (PK) is always in
-- the WAL so no REPLICA IDENTITY FULL is needed for this specific filter.
DROP POLICY IF EXISTS "anon_select_support_conversations_realtime" ON support_conversations;
CREATE POLICY "anon_select_support_conversations_realtime"
  ON support_conversations FOR SELECT
  TO anon
  USING (true);

ALTER TABLE support_conversations REPLICA IDENTITY FULL;
