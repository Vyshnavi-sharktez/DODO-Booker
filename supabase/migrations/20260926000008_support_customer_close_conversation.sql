-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — Customer Close Conversation RPC
--
-- Allows the customer to close their own support conversation ("End Chat").
-- Mirrors admin_close_support_conversation but uses the anon/p_customer_id
-- pattern instead of auth.uid() admin verification.
--
-- The existing AFTER UPDATE trigger (fn_clear_support_reminder_logs_on_status_change)
-- fires on this status change → clears reminder logs → reminders stop.
--
-- Reopen behavior is unchanged: the next customer message (via
-- support_send_customer_message) triggers fn_update_support_conversation_on_message
-- which sets status = 'pending_admin', naturally reopening the conversation.
-- ─────────────────────────────────────────────────────────────────────────────

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

  -- Fetch the customer's conversation.
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
     SET status     = 'closed',
         updated_at = now()
   WHERE id = v_conv_id;
END;
$$;

GRANT EXECUTE ON FUNCTION support_customer_close_conversation(UUID)
  TO anon, authenticated;
