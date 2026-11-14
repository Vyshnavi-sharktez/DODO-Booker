-- No-agent fallback: when no human admin replies within N minutes of a handoff,
-- the bot sends a configurable fallback message.
--
-- Changes:
--   bot_configs             + handoff_timeout_minutes, handoff_timeout_message
--   support_conversations   + last_handoff_at, handoff_timeout_notified
--   fn_support_handoff_timeout_check() — pg_cron target
--   cron job 'support-handoff-timeout' — runs every minute

-- ── 1. New columns on bot_configs ─────────────────────────────────────────────

ALTER TABLE bot_configs
  ADD COLUMN IF NOT EXISTS handoff_timeout_minutes INT NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS handoff_timeout_message TEXT NOT NULL DEFAULT
    'Our support team is currently busy. We''ll get back to you as soon as possible. Thank you for your patience!';

-- ── 2. New columns on support_conversations ───────────────────────────────────

ALTER TABLE support_conversations
  ADD COLUMN IF NOT EXISTS last_handoff_at          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS handoff_timeout_notified BOOLEAN NOT NULL DEFAULT FALSE;

-- ── 3. Timeout check function ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_support_handoff_timeout_check()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_timeout_min  INT;
  v_timeout_msg  TEXT;
  v_bot_admin_id UUID;
  v_conv_id      UUID;
BEGIN
  SELECT
    handoff_timeout_minutes,
    handoff_timeout_message,
    bot_admin_id
  INTO v_timeout_min, v_timeout_msg, v_bot_admin_id
  FROM bot_configs LIMIT 1;

  -- 0 = disabled; also abort if bot admin row is missing
  IF COALESCE(v_timeout_min, 0) = 0 THEN RETURN; END IF;
  IF v_bot_admin_id IS NULL THEN RETURN; END IF;

  FOR v_conv_id IN
    SELECT sc.id
    FROM support_conversations sc
    WHERE sc.last_handoff_at          IS NOT NULL
      AND sc.handoff_timeout_notified = FALSE
      AND sc.status                  <> 'closed'
      AND sc.last_handoff_at          < NOW() - (v_timeout_min || ' minutes')::INTERVAL
      -- No human admin reply after the handoff timestamp
      AND NOT EXISTS (
        SELECT 1 FROM support_messages sm
        WHERE sm.conversation_id = sc.id
          AND sm.sender_type    = 'admin'
          AND sm.sender_id     != v_bot_admin_id
          AND sm.created_at    >= sc.last_handoff_at
      )
  LOOP
    INSERT INTO support_messages (
      conversation_id, sender_type, sender_id, message,
      is_read_by_admin, is_read_by_customer
    ) VALUES (
      v_conv_id,
      'admin',
      v_bot_admin_id,
      v_timeout_msg,
      TRUE,
      FALSE
    );

    UPDATE support_conversations
      SET handoff_timeout_notified = TRUE
    WHERE id = v_conv_id;

    RAISE LOG '[DODO][SupportBot] Handoff timeout message sent for conversation %', v_conv_id;
  END LOOP;
END;
$$;

-- ── 4. Schedule every minute ──────────────────────────────────────────────────

DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'support-handoff-timeout') THEN
    PERFORM cron.unschedule('support-handoff-timeout');
  END IF;
  PERFORM cron.schedule(
    'support-handoff-timeout',
    '* * * * *',
    'SELECT fn_support_handoff_timeout_check()'
  );
END;
$do$;
