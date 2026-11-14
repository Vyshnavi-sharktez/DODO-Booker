-- Support chat data retention.
-- Adds message_retention_days + conversation_retention_days to bot_configs.
-- Daily pg_cron job reads those values and purges old closed conversations/messages.
-- Setting either to 0 disables that cleanup.

-- ── 1. Add retention columns to bot_configs ───────────────────────────────────

ALTER TABLE bot_configs
  ADD COLUMN IF NOT EXISTS message_retention_days      INT NOT NULL DEFAULT 90,
  ADD COLUMN IF NOT EXISTS conversation_retention_days INT NOT NULL DEFAULT 365;

-- ── 2. Cleanup function ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_support_retention_cleanup()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_msg_days  INT;
  v_conv_days INT;
  v_deleted_msgs  INT;
  v_deleted_convs INT;
BEGIN
  SELECT message_retention_days, conversation_retention_days
    INTO v_msg_days, v_conv_days
    FROM bot_configs LIMIT 1;

  -- Delete messages from closed conversations older than retention period
  IF v_msg_days > 0 THEN
    DELETE FROM support_messages
    WHERE conversation_id IN (
      SELECT id FROM support_conversations
      WHERE status    = 'closed'
        AND updated_at < NOW() - (v_msg_days || ' days')::INTERVAL
    );
    GET DIAGNOSTICS v_deleted_msgs = ROW_COUNT;
    RAISE LOG '[DODO][SupportRetention] Deleted % messages (retention: % days)', v_deleted_msgs, v_msg_days;
  END IF;

  -- Delete closed conversations older than retention period
  IF v_conv_days > 0 THEN
    DELETE FROM support_conversations
    WHERE status    = 'closed'
      AND updated_at < NOW() - (v_conv_days || ' days')::INTERVAL;
    GET DIAGNOSTICS v_deleted_convs = ROW_COUNT;
    RAISE LOG '[DODO][SupportRetention] Deleted % conversations (retention: % days)', v_deleted_convs, v_conv_days;
  END IF;
END;
$$;

-- ── 3. Schedule daily at 3am UTC ──────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'support-retention-cleanup') THEN
    PERFORM cron.unschedule('support-retention-cleanup');
  END IF;
  PERFORM cron.schedule(
    'support-retention-cleanup',
    '0 3 * * *',
    'SELECT fn_support_retention_cleanup()'
  );
END;
$do$;
