-- ─────────────────────────────────────────────────────────────────────────────
-- Support Chat — Attachments, Context Links, Idempotent Retry
--
-- 1. Adds attachment_url, attachment_type, context_type, context_id columns to
--    support_messages for file attachments and booking/refund context links.
-- 2. Creates support-chat-attachments private storage bucket with anon/auth
--    read + write policies (mirrors refund-message-attachments pattern).
-- 3. Replaces support_send_customer_message RPC with an updated signature that
--    accepts optional attachment, context, and client-supplied message id
--    params (enabling idempotent retry without duplicate messages).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Table columns ─────────────────────────────────────────────────────────────

ALTER TABLE support_messages
  ADD COLUMN IF NOT EXISTS attachment_url  TEXT,
  ADD COLUMN IF NOT EXISTS attachment_type TEXT,
  ADD COLUMN IF NOT EXISTS context_type    TEXT
    CHECK (context_type IS NULL OR context_type IN ('booking', 'refund')),
  ADD COLUMN IF NOT EXISTS context_id      TEXT;

-- ── Storage bucket ────────────────────────────────────────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'support-chat-attachments',
  'support-chat-attachments',
  false,
  5242880,
  ARRAY['image/jpeg','image/png','image/webp','application/pdf']::text[]
)
ON CONFLICT (id) DO NOTHING;

-- Storage policies — guarded so repeated applies are safe.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'storage' AND tablename = 'objects'
       AND policyname = 'support_attach_anon_upload'
  ) THEN
    CREATE POLICY "support_attach_anon_upload"
      ON storage.objects FOR INSERT TO anon
      WITH CHECK (bucket_id = 'support-chat-attachments');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'storage' AND tablename = 'objects'
       AND policyname = 'support_attach_auth_upload'
  ) THEN
    CREATE POLICY "support_attach_auth_upload"
      ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'support-chat-attachments');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'storage' AND tablename = 'objects'
       AND policyname = 'support_attach_anon_select'
  ) THEN
    CREATE POLICY "support_attach_anon_select"
      ON storage.objects FOR SELECT TO anon
      USING (bucket_id = 'support-chat-attachments');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'storage' AND tablename = 'objects'
       AND policyname = 'support_attach_auth_select'
  ) THEN
    CREATE POLICY "support_attach_auth_select"
      ON storage.objects FOR SELECT TO authenticated
      USING (bucket_id = 'support-chat-attachments');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'storage' AND tablename = 'objects'
       AND policyname = 'support_attach_auth_delete'
  ) THEN
    CREATE POLICY "support_attach_auth_delete"
      ON storage.objects FOR DELETE TO authenticated
      USING (bucket_id = 'support-chat-attachments');
  END IF;
END;
$$;

-- ── Updated RPC: support_send_customer_message ────────────────────────────────
--
-- Added params (all DEFAULT NULL for backward compatibility):
--   p_message_id        — client-supplied UUID; used as message id for idempotent
--                         retry.  ON CONFLICT (id) DO NOTHING prevents duplicates.
--   p_attachment_url    — storage path in support-chat-attachments bucket.
--   p_attachment_type   — MIME type of the attachment.
--   p_context_type      — 'booking' or 'refund'.
--   p_context_id        — UUID of the linked booking or refund_request.
--
-- The old 3-argument signature is dropped first so the new signature can be
-- registered. Existing callers that pass only 3 args continue to work because
-- the new params all have DEFAULT NULL.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS support_send_customer_message(UUID, UUID, TEXT);

CREATE OR REPLACE FUNCTION support_send_customer_message(
  p_customer_id       UUID,
  p_conversation_id   UUID,
  p_message           TEXT,
  p_message_id        UUID    DEFAULT NULL,
  p_attachment_url    TEXT    DEFAULT NULL,
  p_attachment_type   TEXT    DEFAULT NULL,
  p_context_type      TEXT    DEFAULT NULL,
  p_context_id        TEXT    DEFAULT NULL
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
  -- Validate customer exists and is active.
  SELECT id INTO v_customer_id
    FROM customers
   WHERE id = p_customer_id AND is_active = TRUE
   LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found or inactive' USING ERRCODE = '42501';
  END IF;

  -- Require at least message text or an attachment.
  IF p_attachment_url IS NULL AND (p_message IS NULL OR trim(p_message) = '') THEN
    RAISE EXCEPTION 'Message cannot be empty' USING ERRCODE = 'P0001';
  END IF;

  -- Validate conversation belongs to this customer.
  SELECT customer_id INTO v_conv_owner
    FROM support_conversations WHERE id = p_conversation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_conv_owner <> v_customer_id THEN
    RAISE EXCEPTION 'Conversation does not belong to this customer'
      USING ERRCODE = '42501';
  END IF;

  -- Insert; ON CONFLICT (id) DO NOTHING implements idempotent retry — if the
  -- same client_id is retried after a network error, the duplicate is silently
  -- dropped and we return the original message id.
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
