-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — Episode Tracking
--
-- Problem: when a closed conversation is reopened by a customer message, the
-- message list shows all historical messages from every prior episode mixed
-- with the new one.
--
-- Fix: add current_episode_started_at to support_conversations.
--   NULL  → first episode; all messages belong to it.
--   value → set automatically when the first customer message arrives on a
--            closed conversation; only messages with created_at >= this value
--            are returned to the client.
--
-- Changes in this migration:
--   1. ALTER TABLE: add current_episode_started_at TIMESTAMPTZ NULL
--   2. FUNCTION: fn_update_support_conversation_on_message
--                reads old status before UPDATE; sets current_episode_started_at
--                on closed → pending_admin transition.
--   3. FUNCTION: support_get_conversation_messages
--                filters RETURN QUERY by current_episode_started_at.
--   4. FUNCTION: admin_close_support_conversation
--                resets unread counters to 0 on close so the next episode
--                starts with an accurate count.
--   5. FUNCTION: support_customer_close_conversation
--                same counter reset.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Schema ─────────────────────────────────────────────────────────────────

ALTER TABLE support_conversations
  ADD COLUMN IF NOT EXISTS current_episode_started_at TIMESTAMPTZ NULL;

-- ── 2. Trigger: detect reopen and stamp episode start ─────────────────────────

CREATE OR REPLACE FUNCTION fn_update_support_conversation_on_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_status TEXT;
BEGIN
  -- Read the current status BEFORE the UPDATE to detect closed → reopen.
  -- This SELECT runs within the same transaction, so it sees the committed
  -- state that existed just before this trigger fired.
  SELECT status INTO v_old_status
    FROM support_conversations
   WHERE id = NEW.conversation_id;

  UPDATE support_conversations
     SET last_message_at               = NEW.created_at,
         last_message_preview          = left(NEW.message, 120),
         updated_at                    = now(),
         unread_admin_count            = CASE
           WHEN NEW.sender_type = 'customer'
           THEN unread_admin_count + 1
           ELSE unread_admin_count
         END,
         unread_customer_count         = CASE
           WHEN NEW.sender_type = 'admin'
           THEN unread_customer_count + 1
           ELSE unread_customer_count
         END,
         status                        = CASE NEW.sender_type
           WHEN 'customer' THEN 'pending_admin'
           WHEN 'admin'    THEN 'pending_customer'
           ELSE status
         END,
         -- Stamp the episode start when the first customer message opens a
         -- previously closed conversation. Preserved unchanged in all other cases.
         current_episode_started_at    = CASE
           WHEN v_old_status = 'closed' AND NEW.sender_type = 'customer'
           THEN NEW.created_at
           ELSE current_episode_started_at
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

-- Trigger already exists from migration 20260926000003; CREATE OR REPLACE
-- on the function is sufficient — the trigger binding stays in place.

-- ── 3. RPC: filter messages by current episode ────────────────────────────────

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

  -- Validate conversation ownership and fetch episode boundary in one query.
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

  -- Return only current-episode messages.
  -- v_episode_start IS NULL means the first (and only) episode — all messages qualify.
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

-- ── 4. Admin close: reset unread counters ────────────────────────────────────

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
  SELECT id INTO v_admin_id
    FROM admin_users
   WHERE auth_user_id = auth.uid()
     AND is_active = TRUE
   LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: active admin required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM support_conversations WHERE id = p_conversation_id) THEN
    RAISE EXCEPTION 'Conversation not found'
      USING ERRCODE = 'P0002';
  END IF;

  -- Reset unread counters so the next episode starts with accurate counts.
  UPDATE support_conversations
     SET status               = 'closed',
         unread_admin_count   = 0,
         unread_customer_count = 0,
         updated_at           = now()
   WHERE id = p_conversation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_close_support_conversation(UUID)
  TO authenticated;

-- ── 5. Customer close: reset unread counters ─────────────────────────────────

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
     AND is_active = TRUE
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found or inactive'
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
     SET status               = 'closed',
         unread_admin_count   = 0,
         unread_customer_count = 0,
         updated_at           = now()
   WHERE id = v_conv_id;
END;
$$;

GRANT EXECUTE ON FUNCTION support_customer_close_conversation(UUID)
  TO anon, authenticated;
