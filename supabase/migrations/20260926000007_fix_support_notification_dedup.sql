-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: Support Notification Deduplication
--
-- Problem: fn_notify_on_support_message_insert inserts a fresh row for every
-- message, so multiple unread messages from the same customer flood the admin
-- notification panel with duplicate "New Support Message" entries.
--
-- Fix: UPDATE-or-INSERT pattern for both admin and customer notifications:
--   • If an unread notification for this conversation already exists → update
--     its text and timestamp (single row per open episode).
--   • If no unread notification exists → insert a new row.
--
-- This preserves the semantics of the notification (one entry per open
-- conversation episode) without needing a unique constraint.
--
-- Reminder notifications (process_support_reminders) are NOT changed: the
-- max-count / interval behaviour is intentional and controlled by admin config.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_notify_on_support_message_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id   UUID;
  v_customer_name TEXT;
  v_rows_updated  INT;
BEGIN
  IF NEW.sender_type = 'customer' THEN
    -- ── Customer message → notify admin (deduped per conversation episode) ───

    SELECT COALESCE(NULLIF(TRIM(c.full_name), ''), 'A customer'),
           sc.customer_id
      INTO v_customer_name, v_customer_id
      FROM support_conversations sc
      JOIN customers c ON c.id = sc.customer_id
     WHERE sc.id = NEW.conversation_id;

    v_customer_name := COALESCE(v_customer_name, 'A customer');

    -- Refresh existing unread admin notification for this conversation.
    UPDATE notifications
       SET title      = 'New Support Message',
           message    = v_customer_name || ' sent a support message.',
           is_read    = FALSE,
           created_at = NOW()
     WHERE user_type         = 'admin'
       AND entity_type       = 'support_conversation'
       AND entity_id         = NEW.conversation_id
       AND notification_type = 'new_support_message'
       AND is_read           = FALSE;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

    -- No unread notification found → insert a fresh one.
    IF v_rows_updated = 0 THEN
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
    END IF;

  ELSIF NEW.sender_type = 'admin' THEN
    -- ── Admin message → notify customer (deduped per conversation episode) ───

    SELECT customer_id INTO v_customer_id
      FROM support_conversations
     WHERE id = NEW.conversation_id;

    IF v_customer_id IS NOT NULL THEN
      -- Refresh existing unread customer notification for this conversation.
      UPDATE notifications
         SET title      = 'Support Reply',
             message    = 'DODO Support replied to your message.',
             is_read    = FALSE,
             created_at = NOW()
       WHERE user_type         = 'customer'
         AND user_id           = v_customer_id
         AND entity_type       = 'support_conversation'
         AND entity_id         = NEW.conversation_id
         AND notification_type = 'support_reply'
         AND is_read           = FALSE;

      GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

      -- No unread notification found → insert a fresh one.
      IF v_rows_updated = 0 THEN
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
  END IF;

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][SupportChat] fn_notify_on_support_message_insert failed for message %: %',
      NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;
