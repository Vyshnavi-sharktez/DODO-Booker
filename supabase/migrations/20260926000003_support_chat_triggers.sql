-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — Trigger Functions
--
-- Four triggers maintain conversation state, read flags, and cross-party
-- notifications. Mirrors the pattern from 20260923000010 (refund triggers):
--   • SECURITY DEFINER + SET search_path = public
--   • EXCEPTION handlers log failures without aborting the parent operation
--
-- Trigger 1 — BEFORE INSERT on support_messages:
--   fn_support_message_set_own_read_flag
--   Sets is_read_by_admin=true for admin messages, is_read_by_customer=true
--   for customer messages (own messages are immediately read by the sender).
--   Fires BEFORE so the inserted row reflects correct read state from the start.
--
-- Trigger 2 — AFTER INSERT on support_messages:
--   fn_update_support_conversation_on_message
--   Atomically updates last_message_at, last_message_preview, unread counters,
--   and conversation status. Uses UPDATE col = col ± 1 to prevent lost-update
--   races under concurrent admin sessions.
--
-- Trigger 3 — AFTER INSERT on support_messages:
--   fn_notify_on_support_message_insert
--   Customer message → admin broadcast notification.
--   Admin message    → customer personal notification.
--   Non-fatal: notification failure never rolls back the message INSERT.
--
-- Trigger 4 — AFTER UPDATE OF status on support_conversations:
--   fn_clear_support_reminder_logs_on_status_change
--   Deletes all reminder_logs for the conversation when it is closed OR reopened
--   (closed → any). Each open episode starts with a fresh reminder counter.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Trigger 1: BEFORE INSERT — set own-sender read flags ─────────────────────

CREATE OR REPLACE FUNCTION fn_support_message_set_own_read_flag()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- The sender has implicitly read their own message.
  IF NEW.sender_type = 'admin' THEN
    NEW.is_read_by_admin := true;
  ELSIF NEW.sender_type = 'customer' THEN
    NEW.is_read_by_customer := true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_message_set_own_read_flag ON support_messages;
CREATE TRIGGER trg_support_message_set_own_read_flag
  BEFORE INSERT ON support_messages
  FOR EACH ROW
  EXECUTE FUNCTION fn_support_message_set_own_read_flag();

-- ── Trigger 2: AFTER INSERT — update conversation state ──────────────────────

CREATE OR REPLACE FUNCTION fn_update_support_conversation_on_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Atomically update conversation metadata and unread counters.
  -- Counter updates use col ± 1 (not read-modify-write) to avoid races when
  -- two admin sessions are active simultaneously.
  --
  -- Status transitions:
  --   customer message → 'pending_admin'  (admin needs to respond)
  --   admin message    → 'pending_customer' (customer has a new reply)
  --
  -- Note: 'closed' → 'pending_admin' on a customer message reopens the
  -- conversation. fn_clear_support_reminder_logs_on_status_change fires
  -- on that status change and clears the reminder log counter.
  UPDATE support_conversations
     SET last_message_at      = NEW.created_at,
         last_message_preview = left(NEW.message, 120),
         updated_at           = now(),
         unread_admin_count   = CASE
           WHEN NEW.sender_type = 'customer'
           THEN unread_admin_count + 1
           ELSE unread_admin_count
         END,
         unread_customer_count = CASE
           WHEN NEW.sender_type = 'admin'
           THEN unread_customer_count + 1
           ELSE unread_customer_count
         END,
         status = CASE NEW.sender_type
           WHEN 'customer' THEN 'pending_admin'
           WHEN 'admin'    THEN 'pending_customer'
           ELSE status
         END
   WHERE id = NEW.conversation_id;

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][SupportChat] fn_update_support_conversation_on_message failed for message %: %',
      NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_message_update_conversation ON support_messages;
CREATE TRIGGER trg_support_message_update_conversation
  AFTER INSERT ON support_messages
  FOR EACH ROW
  EXECUTE FUNCTION fn_update_support_conversation_on_message();

-- ── Trigger 3: AFTER INSERT — cross-party notifications ──────────────────────

CREATE OR REPLACE FUNCTION fn_notify_on_support_message_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id   UUID;
  v_customer_name TEXT;
BEGIN
  IF NEW.sender_type = 'customer' THEN
    -- ── Customer message → notify all admins ──────────────────────────────
    SELECT COALESCE(NULLIF(TRIM(c.full_name), ''), 'A customer'),
           sc.customer_id
      INTO v_customer_name, v_customer_id
      FROM support_conversations sc
      JOIN customers c ON c.id = sc.customer_id
     WHERE sc.id = NEW.conversation_id;

    v_customer_name := COALESCE(v_customer_name, 'A customer');

    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'admin', NULL,
      'New Support Message',
      v_customer_name || ' sent a support message.',
      'new_support_message',
      'support_conversation', NEW.conversation_id,
      FALSE, NOW()
    );

  ELSIF NEW.sender_type = 'admin' THEN
    -- ── Admin message → notify the customer ──────────────────────────────
    SELECT customer_id INTO v_customer_id
      FROM support_conversations
     WHERE id = NEW.conversation_id;

    IF v_customer_id IS NOT NULL THEN
      INSERT INTO notifications (
        user_type, user_id,
        title, message,
        notification_type, entity_type, entity_id,
        is_read, created_at
      ) VALUES (
        'customer', v_customer_id,
        'Support Reply',
        'DODO Support replied to your message.',
        'support_reply',
        'support_conversation', NEW.conversation_id,
        FALSE, NOW()
      );
    END IF;
  END IF;

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][SupportChat] fn_notify_on_support_message_insert failed for message %: %',
      NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_message_notify ON support_messages;
CREATE TRIGGER trg_support_message_notify
  AFTER INSERT ON support_messages
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_on_support_message_insert();

-- ── Trigger 4: AFTER UPDATE OF status — clear reminder logs ──────────────────

CREATE OR REPLACE FUNCTION fn_clear_support_reminder_logs_on_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Clear reminder logs when:
  --   • Conversation is closed (prevent phantom reminders after closure)
  --   • Conversation is reopened from closed (fresh episode, fresh counter)
  IF OLD.status != NEW.status AND (
    NEW.status = 'closed'
    OR (OLD.status = 'closed' AND NEW.status != 'closed')
  ) THEN
    DELETE FROM support_reminder_logs WHERE conversation_id = NEW.id;
  END IF;

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][SupportChat] fn_clear_support_reminder_logs_on_status_change failed for conversation %: %',
      NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_conv_clear_reminder_logs ON support_conversations;
CREATE TRIGGER trg_support_conv_clear_reminder_logs
  AFTER UPDATE OF status ON support_conversations
  FOR EACH ROW
  EXECUTE FUNCTION fn_clear_support_reminder_logs_on_status_change();
