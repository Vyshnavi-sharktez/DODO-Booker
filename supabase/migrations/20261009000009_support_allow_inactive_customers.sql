-- Allow inactive customers to use support chat.
-- All customer-facing support RPCs are rebuilt to validate existence only
-- (no is_active check) so deactivated accounts can still contact support.
--
-- Fixes vs the first draft of this migration:
--   1. support_send_customer_message: first draft replaced the 3-param
--      signature; the app calls the 8-param version (p_message_id etc.) from
--      20260926000010.  Both are dropped; 8-param recreated without is_active.
--   2. support_get_conversation_messages: restores the current_episode_started_at
--      filter from 20260926000009 that was accidentally dropped.
--   3. support_customer_close_conversation: was missing entirely.

-- ── support_get_or_create_conversation ───────────────────────────────────────
-- Return type was changed to JSONB in 20260926000006 — must DROP to recreate.

DROP FUNCTION IF EXISTS support_get_or_create_conversation(UUID);

CREATE FUNCTION support_get_or_create_conversation(
  p_customer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID;
  v_conv_id     UUID;
  v_conv        RECORD;
BEGIN
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found'
      USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_conv_id
    FROM support_conversations
   WHERE customer_id = v_customer_id
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_conv_id IS NULL THEN
    INSERT INTO support_conversations (customer_id, status)
    VALUES (v_customer_id, 'open')
    RETURNING id INTO v_conv_id;
  END IF;

  SELECT id, customer_id, status, last_message_at, last_message_preview,
         unread_customer_count, created_at, updated_at
    INTO v_conv
    FROM support_conversations
   WHERE id = v_conv_id;

  RETURN jsonb_build_object(
    'id',                    v_conv.id,
    'customer_id',           v_conv.customer_id,
    'status',                v_conv.status,
    'last_message_at',       v_conv.last_message_at,
    'last_message_preview',  v_conv.last_message_preview,
    'unread_customer_count', v_conv.unread_customer_count,
    'created_at',            v_conv.created_at,
    'updated_at',            v_conv.updated_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION support_get_or_create_conversation(UUID)
  TO anon, authenticated;

-- ── support_get_conversation ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION support_get_conversation(
  p_customer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID;
  v_conv        RECORD;
BEGIN
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found'
      USING ERRCODE = '42501';
  END IF;

  SELECT id, status, last_message_at, last_message_preview,
         unread_customer_count, created_at, updated_at
    INTO v_conv
    FROM support_conversations
   WHERE customer_id = v_customer_id
   ORDER BY created_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'id',                    v_conv.id,
    'status',                v_conv.status,
    'last_message_at',       v_conv.last_message_at,
    'last_message_preview',  v_conv.last_message_preview,
    'unread_customer_count', v_conv.unread_customer_count,
    'created_at',            v_conv.created_at,
    'updated_at',            v_conv.updated_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION support_get_conversation(UUID)
  TO anon, authenticated;

-- ── support_send_customer_message ────────────────────────────────────────────
-- Drop both signatures: the 8-param from 20260926000010 (is_active check) and
-- the accidental 3-param created by the first draft of this migration.
-- Recreate only the 8-param — the app always passes p_message_id.

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
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found'
      USING ERRCODE = '42501';
  END IF;

  IF p_attachment_url IS NULL AND (p_message IS NULL OR trim(p_message) = '') THEN
    RAISE EXCEPTION 'Message cannot be empty'
      USING ERRCODE = 'P0001';
  END IF;

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

-- ── support_get_conversation_messages ────────────────────────────────────────
-- Removes is_active check; preserves current_episode_started_at filter
-- from 20260926000009 (episode tracking).

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

-- ── support_mark_messages_read_by_customer ───────────────────────────────────

CREATE OR REPLACE FUNCTION support_mark_messages_read_by_customer(
  p_customer_id     UUID,
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID;
  v_conv_owner  UUID;
BEGIN
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found'
      USING ERRCODE = '42501';
  END IF;

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

  UPDATE support_messages
     SET is_read_by_customer = true
   WHERE conversation_id = p_conversation_id
     AND sender_type     = 'admin'
     AND is_read_by_customer = false;

  UPDATE support_conversations
     SET unread_customer_count = 0,
         updated_at = now()
   WHERE id = p_conversation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION support_mark_messages_read_by_customer(UUID, UUID)
  TO anon, authenticated;

-- ── support_customer_close_conversation ──────────────────────────────────────
-- Replaces the version in 20260926000009 which had AND is_active = TRUE.
-- Preserves the unread counter reset added in that migration.

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
