-- Corrective migration for 20261009000009 which had three defects:
--
--   1. support_send_customer_message: replaced the 3-param signature instead of
--      the 8-param version (p_message_id, attachment, context params) that the
--      app actually calls. The 8-param was left untouched with AND is_active=TRUE.
--      This migration drops the dead 3-param, drops the 8-param, and recreates
--      the 8-param preserving idempotency (ON CONFLICT DO NOTHING), attachment
--      handling, and context links — without the is_active check.
--
--   2. support_get_conversation_messages: the episode filter
--      (current_episode_started_at) introduced in 20260926000009 was dropped.
--      Restored here so customers only see messages from the current episode.
--
--   3. support_customer_close_conversation: was not included at all, leaving
--      AND is_active=TRUE in place. Inactive customers could not end their chat.
--      Recreated with the unread-counter reset from 20260926000009 but without
--      the is_active check.

-- ── 1. support_send_customer_message ─────────────────────────────────────────
-- Drop the dead 3-param created by the previous draft and the 8-param that
-- still blocked inactive customers. Recreate only the 8-param.

DROP FUNCTION IF EXISTS support_send_customer_message(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS support_send_customer_message(UUID, UUID, TEXT, UUID, TEXT, TEXT, TEXT, TEXT);

CREATE FUNCTION support_send_customer_message(
  p_customer_id       UUID,
  p_conversation_id   UUID,
  p_message           TEXT,
  p_message_id        UUID  DEFAULT NULL,
  p_attachment_url    TEXT  DEFAULT NULL,
  p_attachment_type   TEXT  DEFAULT NULL,
  p_context_type      TEXT  DEFAULT NULL,
  p_context_id        TEXT  DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID;
  v_conv_owner  UUID;
  v_message_id  UUID := COALESCE(p_message_id, gen_random_uuid());
BEGIN
  -- Validate customer exists (no is_active check — inactive customers can chat).
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found'
      USING ERRCODE = '42501';
  END IF;

  -- Require text or an attachment.
  IF p_attachment_url IS NULL AND (p_message IS NULL OR trim(p_message) = '') THEN
    RAISE EXCEPTION 'Message cannot be empty'
      USING ERRCODE = 'P0001';
  END IF;

  -- Validate conversation belongs to this customer.
  SELECT customer_id INTO v_conv_owner
    FROM support_conversations
   WHERE id = p_conversation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_conv_owner <> v_customer_id THEN
    RAISE EXCEPTION 'Conversation does not belong to this customer'
      USING ERRCODE = '42501';
  END IF;

  -- Idempotent insert: if the client retries with the same p_message_id after a
  -- network error the duplicate is silently dropped and the original id returned.
  INSERT INTO support_messages (
    id, conversation_id, sender_type, sender_id, message,
    attachment_url, attachment_type, context_type, context_id
  ) VALUES (
    v_message_id,
    p_conversation_id,
    'customer',
    v_customer_id,
    COALESCE(trim(p_message), ''),
    p_attachment_url,
    p_attachment_type,
    p_context_type,
    p_context_id
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN v_message_id;
END;
$$;

GRANT EXECUTE ON FUNCTION support_send_customer_message(UUID, UUID, TEXT, UUID, TEXT, TEXT, TEXT, TEXT)
  TO anon, authenticated;

-- ── 2. support_get_conversation_messages ─────────────────────────────────────
-- Restores the current_episode_started_at filter from 20260926000009 that was
-- dropped by 20261009000009. Without it every historical message across all
-- episodes was shown instead of only the current episode's messages.

CREATE OR REPLACE FUNCTION support_get_conversation_messages(
  p_customer_id     UUID,
  p_conversation_id UUID
)
RETURNS SETOF support_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id   UUID;
  v_conv_owner    UUID;
  v_episode_start TIMESTAMPTZ;
BEGIN
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found'
      USING ERRCODE = '42501';
  END IF;

  SELECT customer_id, current_episode_started_at
    INTO v_conv_owner, v_episode_start
    FROM support_conversations
   WHERE id = p_conversation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_conv_owner <> v_customer_id THEN
    RAISE EXCEPTION 'Conversation does not belong to this customer'
      USING ERRCODE = '42501';
  END IF;

  -- NULL episode_start means the first (and only) episode — all messages qualify.
  RETURN QUERY
    SELECT *
      FROM support_messages
     WHERE conversation_id = p_conversation_id
       AND (v_episode_start IS NULL OR created_at >= v_episode_start)
     ORDER BY created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION support_get_conversation_messages(UUID, UUID)
  TO anon, authenticated;

-- ── 3. support_customer_close_conversation ───────────────────────────────────
-- Was omitted entirely from 20261009000009. Recreated here without is_active
-- check, preserving the unread-counter reset from 20260926000009 and the
-- no-op guard for already-closed conversations.

CREATE OR REPLACE FUNCTION support_customer_close_conversation(
  p_customer_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID;
  v_conv_id     UUID;
  v_conv_status TEXT;
BEGIN
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found'
      USING ERRCODE = '42501';
  END IF;

  SELECT id, status INTO v_conv_id, v_conv_status
    FROM support_conversations
   WHERE customer_id = v_customer_id
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_conv_id IS NULL THEN
    RAISE EXCEPTION 'No conversation found for this customer'
      USING ERRCODE = 'P0002';
  END IF;

  -- No-op if already closed (idempotent).
  IF v_conv_status = 'closed' THEN
    RETURN;
  END IF;

  UPDATE support_conversations
     SET status                = 'closed',
         unread_admin_count    = 0,
         unread_customer_count = 0,
         updated_at            = now()
   WHERE id = v_conv_id;
END;
$$;

GRANT EXECUTE ON FUNCTION support_customer_close_conversation(UUID)
  TO anon, authenticated;
