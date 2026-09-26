-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — Configurable Auto-Close for Inactivity
--
-- Two components:
--   1. Settings rows — two keys in the existing `settings` table control
--      auto-close behaviour without a schema change.
--   2. process_support_auto_close() — SECURITY DEFINER function that reads the
--      config, finds qualifying inactive conversations, and closes them.
--   3. pg_cron schedule — calls process_support_auto_close() every hour.
--      The hour cadence is the resolution; actual idle threshold is governed by
--      support_auto_close_idle_hours (default 24 h).
--
-- Configuration keys (setting_key / setting_value):
--   support_auto_close_enabled       'true' | 'false'   master on/off switch
--   support_auto_close_idle_hours    integer (hours)     inactivity threshold
--
-- Inactivity timer: last_message_at is updated by the existing
-- fn_update_support_conversation_on_message trigger on every INSERT into
-- support_messages, so any message (customer or admin) resets the clock.
--
-- Auto-close eligibility (all must hold):
--   • status != 'closed'  (idempotent: already-closed rows are never touched)
--   • last_message_at IS NOT NULL  (must have at least one message)
--   • last_message_at < now() - (idle_hours * '1 hour'::interval)
--
-- Side effects on close:
--   • fn_clear_support_reminder_logs_on_status_change trigger fires automatically,
--     deleting all support_reminder_logs rows → stops further reminders.
--   • Realtime publication (support_conversations) delivers the status change to
--     the customer app, which already handles status = 'closed' gracefully.
--   • Admin inbox: conversation moves to the Closed tab with no extra action.
--
-- Starting a new chat after auto-close:
--   • Customer sends a message → existing fn_update_support_conversation_on_message
--     trigger reopens the conversation (closed → pending_admin) and stamps
--     current_episode_started_at = now() → fresh episode, old messages hidden.
--
-- Safety / idempotency:
--   • status != 'closed' guard ensures a conversation is never re-closed.
--   • Manually closed conversations remain untouched (already status = 'closed').
--   • EXCEPTION block prevents a single failure from aborting the whole run.
--   • pg_cron job registration is guarded by IF NOT EXISTS.
--   • ON CONFLICT DO NOTHING on settings seed preserves admin-customised values.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Settings seed ─────────────────────────────────────────────────────────

INSERT INTO settings (setting_key, setting_value)
VALUES
  ('support_auto_close_enabled',    'false'),
  ('support_auto_close_idle_hours', '24')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 2. Auto-close function ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION process_support_auto_close()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled    TEXT;
  v_idle_hours INT := 24;   -- default used if setting missing or invalid
BEGIN
  -- ── Read config ────────────────────────────────────────────────────────────

  SELECT setting_value INTO v_enabled
    FROM settings
   WHERE setting_key = 'support_auto_close_enabled';

  -- Default to disabled when key is missing — never auto-close unexpectedly.
  IF COALESCE(v_enabled, 'false') <> 'true' THEN
    RETURN;
  END IF;

  -- Safe-cast idle_hours: EXCEPTION catches invalid text → use default.
  BEGIN
    SELECT setting_value::INT INTO v_idle_hours
      FROM settings
     WHERE setting_key = 'support_auto_close_idle_hours';
  EXCEPTION WHEN OTHERS THEN
    v_idle_hours := NULL;
  END;
  -- NULLIF guards against a stored '0' which would close every conversation instantly.
  v_idle_hours := COALESCE(NULLIF(v_idle_hours, 0), 24);

  -- ── Close inactive conversations ───────────────────────────────────────────
  --
  -- Eligibility:
  --   • status != 'closed'   → idempotent; manually closed rows unaffected
  --   • last_message_at IS NOT NULL  → must have had activity
  --   • last_message_at < cutoff     → idle longer than the configured period
  --
  -- Setting unread counts to 0 prevents stale badge counts after close.
  -- The fn_clear_support_reminder_logs_on_status_change trigger fires on each
  -- updated row, deleting reminder_logs and stopping further reminder delivery.

  UPDATE support_conversations
  SET
    status                = 'closed',
    unread_admin_count    = 0,
    unread_customer_count = 0,
    updated_at            = now()
  WHERE
    status          != 'closed'
    AND last_message_at IS NOT NULL
    AND last_message_at < now() - (v_idle_hours * INTERVAL '1 hour');

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][SupportChat] process_support_auto_close failed: %', SQLERRM;
END;
$$;

-- ── 3. pg_cron schedule ───────────────────────────────────────────────────────
-- pg_cron is already enabled (reminder job uses it; see 20260926000005).

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  -- Idempotent: skip if job already registered.
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'support-auto-close'
  ) THEN
    PERFORM cron.schedule(
      'support-auto-close',
      '0 * * * *',           -- top of every hour; idle threshold enforced in function
      'SELECT public.process_support_auto_close()'
    );
    RAISE LOG '[DODO][SupportChat] pg_cron job support-auto-close registered.';
  END IF;
END;
$$;
