-- Fix: notifications realtime column filter silently drops events.
--
-- Root cause:
--   The admin panel subscribes to the notifications table with a column filter
--   (user_type=eq.admin). Supabase Realtime requires REPLICA IDENTITY FULL on
--   RLS-enabled tables for column-filtered postgres_changes subscriptions to
--   deliver events. Without it, WAL events are dropped or arrive with empty
--   payloads, so the notifications panel only updates after a full browser
--   refresh (which re-runs the initial SELECT query).
--
--   Push notifications are unaffected — they fire from fn_send_push_on_notification_insert
--   via pg_net, which is independent of Supabase Realtime.
--
-- Precedent in this codebase:
--   20261009000011 — same fix for support_messages / support_conversations
--   20261021000002 — same fix for bookings

ALTER TABLE public.notifications REPLICA IDENTITY FULL;
