-- Support handoff UX:
-- 1. Expand sender_type to allow 'system' (for "agent joined" messages)
-- 2. Trigger: auto-insert system message when first human admin replies
-- Admin push notification is handled by the Edge Function (not here).

-- ── 1. Expand sender_type constraint ─────────────────────────────────────────

DO $$
DECLARE v_conname TEXT;
BEGIN
  SELECT conname INTO v_conname
  FROM pg_constraint
  WHERE conrelid = 'support_messages'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%sender_type%';
  IF v_conname IS NOT NULL THEN
    EXECUTE 'ALTER TABLE support_messages DROP CONSTRAINT ' || quote_ident(v_conname);
  END IF;
END;
$$;

ALTER TABLE support_messages
  ADD CONSTRAINT support_messages_sender_type_check
  CHECK (sender_type IN ('customer', 'admin', 'system'));

-- ── 2. Agent joined trigger ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_agent_joined_message()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_bot_admin_id UUID := 'a0000000-b070-0000-0000-000000000000'::UUID;
BEGIN
  -- Only fires for human admin messages (not bot, not customer, not system)
  IF NEW.sender_type <> 'admin' OR NEW.sender_id = v_bot_admin_id THEN
    RETURN NEW;
  END IF;

  -- Only insert system message for the FIRST human admin reply in a conversation
  IF EXISTS (
    SELECT 1 FROM support_messages
    WHERE conversation_id = NEW.conversation_id
      AND sender_type     = 'admin'
      AND sender_id      != v_bot_admin_id
      AND id             != NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  -- Insert "agent joined" system message 1ms before the admin's first message
  INSERT INTO support_messages (
    conversation_id, sender_type, sender_id, message,
    is_read_by_admin, is_read_by_customer, created_at
  ) VALUES (
    NEW.conversation_id,
    'system',
    NEW.sender_id,
    'An agent has joined the conversation',
    TRUE,
    FALSE,
    NEW.created_at - INTERVAL '1 millisecond'
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE LOG '[DODO][Support] fn_agent_joined_message failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_agent_joined_message ON support_messages;
CREATE TRIGGER trg_agent_joined_message
  AFTER INSERT ON support_messages
  FOR EACH ROW EXECUTE FUNCTION fn_agent_joined_message();
