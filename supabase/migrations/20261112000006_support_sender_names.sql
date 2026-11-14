-- Add sender_name to support_messages.
-- Populated by a BEFORE INSERT trigger so both initial fetch and Realtime
-- events carry the name without any client-side join.

ALTER TABLE support_messages
  ADD COLUMN IF NOT EXISTS sender_name TEXT;

-- ── Populate sender_name on every INSERT ──────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_support_message_set_sender_name()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NEW.sender_type = 'admin' THEN
    SELECT full_name INTO NEW.sender_name
      FROM admin_users WHERE id = NEW.sender_id LIMIT 1;

  ELSIF NEW.sender_type = 'customer' THEN
    SELECT full_name INTO NEW.sender_name
      FROM customers WHERE id = NEW.sender_id LIMIT 1;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_message_set_sender_name ON support_messages;
CREATE TRIGGER trg_support_message_set_sender_name
  BEFORE INSERT ON support_messages
  FOR EACH ROW EXECUTE FUNCTION fn_support_message_set_sender_name();

-- ── Update agent-joined message to use real admin name ────────────────────────

CREATE OR REPLACE FUNCTION fn_agent_joined_message()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_bot_admin_id UUID := 'a0000000-b070-0000-0000-000000000000'::UUID;
  v_admin_name   TEXT;
BEGIN
  IF NEW.sender_type <> 'admin' OR NEW.sender_id = v_bot_admin_id THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM support_messages
    WHERE conversation_id = NEW.conversation_id
      AND sender_type     = 'admin'
      AND sender_id      != v_bot_admin_id
      AND id             != NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  SELECT full_name INTO v_admin_name
    FROM admin_users WHERE id = NEW.sender_id LIMIT 1;

  INSERT INTO support_messages (
    conversation_id, sender_type, sender_id, message,
    is_read_by_admin, is_read_by_customer, created_at
  ) VALUES (
    NEW.conversation_id,
    'system',
    NEW.sender_id,
    COALESCE(v_admin_name, 'An agent') || ' has joined the conversation',
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
