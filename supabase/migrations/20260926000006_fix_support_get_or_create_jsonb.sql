-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: support_get_or_create_conversation return type UUID → JSONB
--
-- The original function (20260926000002) returned UUID. The customer app calls
-- SupportConversation.fromMap() on the result, which requires a Map/JSONB.
-- PostgreSQL does not allow changing a function's return type with CREATE OR
-- REPLACE; the function must be dropped and recreated.
--
-- New return: JSONB with all fields needed to construct SupportConversation
-- on the client (id, customer_id, status, last_message_at,
-- last_message_preview, unread_customer_count, created_at, updated_at).
--
-- The admin panel never calls this function (uses direct SELECT instead),
-- so the return type change is backward-compatible.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS support_get_or_create_conversation(UUID);

CREATE OR REPLACE FUNCTION support_get_or_create_conversation(
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

  -- Fetch the full conversation row for the client.
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
