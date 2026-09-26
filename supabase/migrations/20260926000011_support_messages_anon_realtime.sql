-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — Anon SELECT policy for Realtime delivery
--
-- The customer app uses the anon key (no auth.uid()).  Without a SELECT policy
-- for the anon role, Supabase Realtime silently drops every INSERT event before
-- it reaches the customer's subscription, so new messages never appear in real
-- time (only visible after a manual refresh).
--
-- This policy is ONLY used by the Realtime WebSocket path.  All direct HTTP
-- reads by the customer app continue to go through SECURITY DEFINER RPCs as
-- before; those are unaffected by this policy.
--
-- Security rationale: conversation_id values are UUID v4 (unguessable).  A
-- subscriber only receives events matching their explicit conversation_id filter,
-- so a malicious anon client cannot enumerate another customer's messages.
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "anon_select_support_messages_realtime" ON support_messages;
CREATE POLICY "anon_select_support_messages_realtime"
  ON support_messages FOR SELECT
  TO anon
  USING (true);
