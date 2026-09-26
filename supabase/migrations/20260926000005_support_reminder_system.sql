-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — Configurable Reminder System
--
-- Three components:
--   1. Settings rows — three keys in the existing `settings` table control
--      reminder behaviour without a schema change.
--   2. process_support_reminders() — SECURITY DEFINER function that reads the
--      config, finds qualifying conversations, and inserts admin notifications.
--   3. pg_cron schedule — calls process_support_reminders() every 15 minutes.
--      The 15-minute cadence is the resolution; actual reminder intervals are
--      governed by support_reminder_interval_minutes (default 60 min).
--
-- Configuration keys (setting_key / setting_value):
--   support_reminder_enabled           'true' | 'false'  master on/off switch
--   support_reminder_interval_minutes  integer (minutes) min time between reminders
--   support_reminder_max_count         integer           max reminders per episode
--
-- Reminder eligibility:
--   • Conversation status = 'pending_admin' (has unread customer messages)
--   • Oldest unread customer message older than support_reminder_interval_minutes
--   • Reminders sent this episode < support_reminder_max_count
--   • Either no prior reminder OR last reminder older than interval
--
-- Reminders stop automatically when:
--   • Admin reads the conversation (admin_mark_support_conversation_read RPC
--     → unread_admin_count = 0 → status ≠ 'pending_admin')
--   • Conversation is closed (trigger clears reminder_logs → counter resets)
--   • support_reminder_max_count is reached
--   • support_reminder_enabled = 'false'
--
-- pg_cron: already in use by amc_expiry_cron (20260911000006) and
-- warranty_expiry_cron (20260911000007). No new extension dependency.
--
-- All three components are idempotent.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Settings seed ─────────────────────────────────────────────────────────
-- ON CONFLICT DO NOTHING preserves admin-customised values from overwrite.

INSERT INTO settings (setting_key, setting_value)
VALUES
  ('support_reminder_enabled',            'true'),
  ('support_reminder_interval_minutes',   '60'),
  ('support_reminder_max_count',          '3')
ON CONFLICT (setting_key) DO NOTHING;

-- ── 2. Reminder function ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION process_support_reminders()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled   TEXT;
  v_interval  INT := 60;   -- minutes; default used if setting missing or invalid
  v_max_count INT := 3;    -- default
  r           RECORD;
BEGIN
  -- ── Read config ────────────────────────────────────────────────────────────

  SELECT setting_value INTO v_enabled
    FROM settings
   WHERE setting_key = 'support_reminder_enabled';

  -- Default to enabled when key is missing.
  IF COALESCE(v_enabled, 'true') = 'false' THEN
    RETURN;
  END IF;

  -- Safe-cast interval: sub-block EXCEPTION catches invalid text → use default.
  BEGIN
    SELECT setting_value::INT INTO v_interval
      FROM settings
     WHERE setting_key = 'support_reminder_interval_minutes';
  EXCEPTION WHEN OTHERS THEN
    v_interval := NULL;
  END;
  -- NULLIF guards against a stored '0' which would cause instant re-fire loops.
  v_interval := COALESCE(NULLIF(v_interval, 0), 60);

  -- Safe-cast max_count.
  BEGIN
    SELECT setting_value::INT INTO v_max_count
      FROM settings
     WHERE setting_key = 'support_reminder_max_count';
  EXCEPTION WHEN OTHERS THEN
    v_max_count := NULL;
  END;
  v_max_count := COALESCE(NULLIF(v_max_count, 0), 3);

  -- ── Find conversations needing a reminder ───────────────────────────────────
  --
  -- Criteria (all must hold):
  --   a) status = 'pending_admin' — admin has unread customer message(s)
  --   b) oldest unread customer message older than v_interval minutes
  --   c) reminders sent this episode < v_max_count
  --   d) no reminder sent yet, OR last reminder > v_interval minutes ago
  --
  -- Uses CTEs for clarity. Uses v_interval * INTERVAL '1 minute' to avoid
  -- string-cast dynamic SQL.

  FOR r IN
    WITH unread_msgs AS (
      SELECT
        sm.conversation_id,
        MIN(sm.created_at) AS oldest_unread_at
      FROM support_messages sm
      WHERE sm.sender_type     = 'customer'
        AND sm.is_read_by_admin = false
      GROUP BY sm.conversation_id
    ),
    reminder_state AS (
      SELECT
        srl.conversation_id,
        COUNT(*)         AS reminder_count,
        MAX(srl.sent_at) AS last_reminder_at
      FROM support_reminder_logs srl
      GROUP BY srl.conversation_id
    )
    SELECT
      sc.id                                   AS conversation_id,
      COALESCE(rs.reminder_count, 0)::INT     AS reminder_count,
      rs.last_reminder_at
    FROM support_conversations sc
    JOIN unread_msgs um ON um.conversation_id = sc.id
    LEFT JOIN reminder_state rs ON rs.conversation_id = sc.id
    WHERE
      -- a) has unread customer message waiting for admin
      sc.status = 'pending_admin'
      -- b) oldest unread message is older than the configured interval
      AND um.oldest_unread_at < now() - (v_interval * INTERVAL '1 minute')
      -- c) reminder count for this episode below max
      AND COALESCE(rs.reminder_count, 0) < v_max_count
      -- d) no prior reminder, OR last reminder is old enough
      AND (
        rs.last_reminder_at IS NULL
        OR rs.last_reminder_at < now() - (v_interval * INTERVAL '1 minute')
      )
  LOOP
    -- Insert admin broadcast reminder notification.
    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'admin', NULL,
      'Unread Support Message',
      'A customer support message is still waiting for a reply.',
      'support_reminder',
      'support_conversation', r.conversation_id,
      FALSE, NOW()
    );

    -- Record that a reminder was sent (used for count + interval checks above).
    INSERT INTO support_reminder_logs (conversation_id)
    VALUES (r.conversation_id);
  END LOOP;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][SupportChat] process_support_reminders failed: %', SQLERRM;
END;
$$;

-- ── 3. pg_cron schedule ───────────────────────────────────────────────────────
-- pg_cron is already enabled (see 20260911000006_amc_expiry_cron.sql).
-- CREATE EXTENSION IF NOT EXISTS is a no-op when already installed.

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  -- Idempotent: skip if job already registered.
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'process-support-reminders'
  ) THEN
    PERFORM cron.schedule(
      'process-support-reminders',
      '*/15 * * * *',        -- every 15 minutes (interval enforcement is in the function)
      'SELECT public.process_support_reminders()'
    );
    RAISE LOG '[DODO][SupportChat] pg_cron job process-support-reminders registered.';
  END IF;
END;
$$;
