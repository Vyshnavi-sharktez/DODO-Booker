-- Fix support message retention to delete by created_at regardless of conversation status.
-- Previously only deleted messages from closed conversations; now deletes any message
-- older than message_retention_days based on its own created_at.

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

  -- Delete messages older than retention period regardless of conversation status
  IF v_msg_days > 0 THEN
    DELETE FROM support_messages
    WHERE created_at < NOW() - (v_msg_days || ' days')::INTERVAL;
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
