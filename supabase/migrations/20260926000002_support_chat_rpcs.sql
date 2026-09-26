-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — SECURITY DEFINER RPCs
--
-- Customer app auth model: anon role, auth.uid() = NULL, customer_id passed as
-- p_customer_id and verified server-side (same pattern as customer_add_refund_message
-- in 20260922000016).
--
-- All functions:
--   • SECURITY DEFINER — bypasses RLS to read/write support tables safely.
--   • SET search_path = public — prevents search_path injection.
--   • GRANT TO anon, authenticated — supports current anon auth and future
--     Supabase Auth migration.
--   • Validate p_customer_id exists and is active before any data access.
--   • Never expose data from other customers.
--
-- Customer RPCs (5):
--   support_get_or_create_conversation   — enter chat; creates conversation on first use
--   support_get_conversation             — read conversation metadata (status, unread count)
--   support_send_customer_message        — post a message (reopens closed conversations)
--   support_get_conversation_messages    — fetch message thread
--   support_mark_messages_read_by_customer — mark admin messages as read by customer
--
-- Admin RPCs (2):
--   admin_mark_support_conversation_read — atomic read + status transition
--   admin_close_support_conversation     — close a conversation
--
-- Triggers handle: unread counter updates, conversation status transitions,
-- read-flag pre-setting, notifications (migration 20260926000003).
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: support_get_or_create_conversation
--
-- Returns the conversation UUID for this customer, creating one if none exists.
-- If a conversation already exists (regardless of status, including 'closed'),
-- returns it without modification. The conversation status is only changed when
-- a message is actually sent (handled by the AFTER INSERT trigger).
--
-- Invariant: one conversation per customer for Phase 1.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION support_get_or_create_conversation(
  p_customer_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID;
  v_conv_id     UUID;
BEGIN
  -- Validate customer exists and is active.
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
     AND is_active = TRUE
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found or inactive'
      USING ERRCODE = '42501';
  END IF;

  -- Look up existing conversation (most recent, in case of data anomaly).
  SELECT id INTO v_conv_id
    FROM support_conversations
   WHERE customer_id = v_customer_id
   ORDER BY created_at DESC
   LIMIT 1;

  -- Create new conversation if none exists.
  IF v_conv_id IS NULL THEN
    INSERT INTO support_conversations (customer_id, status)
    VALUES (v_customer_id, 'open')
    RETURNING id INTO v_conv_id;
  END IF;

  RETURN v_conv_id;
END;
$$;

GRANT EXECUTE ON FUNCTION support_get_or_create_conversation(UUID)
  TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: support_get_conversation
--
-- Returns conversation metadata as JSONB. Returns NULL if no conversation exists.
-- Used by the customer app to read status ('closed' banner), unread count (badge).
-- ─────────────────────────────────────────────────────────────────────────────

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
  -- Validate customer.
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
     AND is_active = TRUE
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found or inactive'
      USING ERRCODE = '42501';
  END IF;

  -- Fetch conversation.
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

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: support_send_customer_message
--
-- Inserts a customer message. Validates:
--   • p_customer_id is active
--   • conversation belongs to that customer
--   • message is not blank
--
-- Closed conversations are allowed — the AFTER INSERT trigger (migration
-- 20260926000003) reopens them by setting status = 'pending_admin'.
--
-- Returns the new message UUID.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION support_send_customer_message(
  p_customer_id     UUID,
  p_conversation_id UUID,
  p_message         TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID;
  v_conv_owner  UUID;
  v_message_id  UUID;
BEGIN
  -- Validate customer.
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
     AND is_active = TRUE
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found or inactive'
      USING ERRCODE = '42501';
  END IF;

  -- Validate message content.
  IF p_message IS NULL OR trim(p_message) = '' THEN
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

  -- Insert message.
  -- The BEFORE INSERT trigger sets is_read_by_customer = true (own message).
  -- The AFTER INSERT trigger updates conversation state and sends notification.
  INSERT INTO support_messages (
    conversation_id,
    sender_type,
    sender_id,
    message
  ) VALUES (
    p_conversation_id,
    'customer',
    v_customer_id,
    trim(p_message)
  )
  RETURNING id INTO v_message_id;

  RETURN v_message_id;
END;
$$;

GRANT EXECUTE ON FUNCTION support_send_customer_message(UUID, UUID, TEXT)
  TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: support_get_conversation_messages
--
-- Returns all messages for a conversation, oldest first.
-- Validates that the conversation belongs to the requesting customer.
-- ─────────────────────────────────────────────────────────────────────────────

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
  v_customer_id UUID;
  v_conv_owner  UUID;
BEGIN
  -- Validate customer.
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
     AND is_active = TRUE
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found or inactive'
      USING ERRCODE = '42501';
  END IF;

  -- Validate conversation ownership.
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

  RETURN QUERY
    SELECT *
      FROM support_messages
     WHERE conversation_id = p_conversation_id
     ORDER BY created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION support_get_conversation_messages(UUID, UUID)
  TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: support_mark_messages_read_by_customer
--
-- Marks all admin messages in the conversation as read by the customer.
-- Resets unread_customer_count to 0.
-- Called when the customer opens or scrolls to the bottom of the chat screen.
-- ─────────────────────────────────────────────────────────────────────────────

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
  -- Validate customer.
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id
     AND is_active = TRUE
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found or inactive'
      USING ERRCODE = '42501';
  END IF;

  -- Validate conversation ownership.
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

  -- Mark all unread admin messages as read by customer.
  UPDATE support_messages
     SET is_read_by_customer = true
   WHERE conversation_id = p_conversation_id
     AND sender_type     = 'admin'
     AND is_read_by_customer = false;

  -- Reset unread counter atomically.
  UPDATE support_conversations
     SET unread_customer_count = 0,
         updated_at = now()
   WHERE id = p_conversation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION support_mark_messages_read_by_customer(UUID, UUID)
  TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: admin_mark_support_conversation_read
--
-- Called by the admin panel when a conversation is opened/selected.
-- Atomically:
--   1. Marks all unread customer messages as read by admin.
--   2. Resets unread_admin_count to 0.
--   3. Transitions status pending_admin → pending_customer.
--
-- Using an RPC rather than direct UPDATE ensures the status transition and
-- counter reset always happen together; prevents partial state in the UI.
--
-- GRANT TO authenticated only (admin-panel users only).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_mark_support_conversation_read(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  -- Verify active admin.
  SELECT id INTO v_admin_id
    FROM admin_users
   WHERE auth_user_id = auth.uid()
     AND is_active = TRUE
   LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: active admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Validate conversation exists.
  IF NOT EXISTS (SELECT 1 FROM support_conversations WHERE id = p_conversation_id) THEN
    RAISE EXCEPTION 'Conversation not found'
      USING ERRCODE = 'P0002';
  END IF;

  -- Mark all unread customer messages as read by admin.
  UPDATE support_messages
     SET is_read_by_admin = true
   WHERE conversation_id = p_conversation_id
     AND sender_type     = 'customer'
     AND is_read_by_admin = false;

  -- Reset unread counter and transition status.
  UPDATE support_conversations
     SET unread_admin_count = 0,
         status = CASE
           WHEN status = 'pending_admin' THEN 'pending_customer'
           ELSE status
         END,
         updated_at = now()
   WHERE id = p_conversation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_mark_support_conversation_read(UUID)
  TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: admin_close_support_conversation
--
-- Admin closes a conversation. The AFTER UPDATE trigger (migration 20260926000003)
-- clears all reminder logs for the conversation on this status change.
--
-- GRANT TO authenticated only.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_close_support_conversation(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  -- Verify active admin.
  SELECT id INTO v_admin_id
    FROM admin_users
   WHERE auth_user_id = auth.uid()
     AND is_active = TRUE
   LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: active admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Validate conversation exists.
  IF NOT EXISTS (SELECT 1 FROM support_conversations WHERE id = p_conversation_id) THEN
    RAISE EXCEPTION 'Conversation not found'
      USING ERRCODE = 'P0002';
  END IF;

  UPDATE support_conversations
     SET status     = 'closed',
         updated_at = now()
   WHERE id = p_conversation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_close_support_conversation(UUID)
  TO authenticated;
