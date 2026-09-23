-- ─────────────────────────────────────────────────────────────────────────────
-- Refund Message Attachments
--
-- 1. Adds attachment_urls TEXT[] to refund_messages for multi-image support.
--    The original single-attachment attachment_url column is retained for
--    backward compatibility; new code uses attachment_urls exclusively.
--
-- 2. Creates private storage bucket refund-message-attachments.
--    • Max file size: 5 MB
--    • Allowed MIME types: image/jpeg, image/png, image/webp
--    • Private (public = false) — all access requires signed URLs or auth
--
-- 3. Storage RLS policies:
--    • Admins (authenticated, active admin_users record): full access
--    • Anon customers: INSERT (upload) and SELECT (signed URL generation)
--      for any path whose first segment is a valid refund_request_id UUID.
--      Ownership is verified at the application layer (RPC / repository) —
--      the same security model used throughout the anon customer API.
--
-- 4. Updates customer_add_refund_message RPC:
--    • Adds p_attachment_urls TEXT[] parameter (default '{}').
--    • Merges legacy p_attachment_url (single) into the array if provided.
--    • Saves attachment_urls on insert.
--    • Keeps full backward compatibility with the existing 4-arg signature.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Schema change ──────────────────────────────────────────────────────────

ALTER TABLE refund_messages
  ADD COLUMN IF NOT EXISTS attachment_urls TEXT[] NOT NULL DEFAULT '{}';

-- ── 2. Storage bucket ─────────────────────────────────────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'refund-message-attachments',
  'refund-message-attachments',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- ── 3. Storage RLS policies ───────────────────────────────────────────────────

-- Admins: unrestricted access within the bucket.
DROP POLICY IF EXISTS "admin_all_refund_msg_attachments" ON storage.objects;
CREATE POLICY "admin_all_refund_msg_attachments"
  ON storage.objects FOR ALL
  TO authenticated
  USING (
    bucket_id = 'refund-message-attachments'
    AND EXISTS (
      SELECT 1 FROM public.admin_users
       WHERE auth_user_id = auth.uid()
         AND is_active = TRUE
    )
  )
  WITH CHECK (
    bucket_id = 'refund-message-attachments'
    AND EXISTS (
      SELECT 1 FROM public.admin_users
       WHERE auth_user_id = auth.uid()
         AND is_active = TRUE
    )
  );

-- Anon customers: INSERT — path must start with a valid refund_request_id UUID.
-- This prevents arbitrary bucket pollution while preserving the anon auth model.
DROP POLICY IF EXISTS "anon_insert_refund_msg_attachments" ON storage.objects;
CREATE POLICY "anon_insert_refund_msg_attachments"
  ON storage.objects FOR INSERT
  TO anon
  WITH CHECK (
    bucket_id = 'refund-message-attachments'
    AND EXISTS (
      SELECT 1 FROM public.refund_requests
       WHERE id::text = split_part(name, '/', 1)
    )
  );

-- Anon customers: SELECT — same path restriction (needed for signed URL generation).
DROP POLICY IF EXISTS "anon_select_refund_msg_attachments" ON storage.objects;
CREATE POLICY "anon_select_refund_msg_attachments"
  ON storage.objects FOR SELECT
  TO anon
  USING (
    bucket_id = 'refund-message-attachments'
    AND EXISTS (
      SELECT 1 FROM public.refund_requests
       WHERE id::text = split_part(name, '/', 1)
    )
  );

-- ── 4. Updated customer_add_refund_message RPC ────────────────────────────────

CREATE OR REPLACE FUNCTION customer_add_refund_message(
  p_request_id      UUID,
  p_message         TEXT,
  p_attachment_url  TEXT    DEFAULT NULL,   -- legacy single-attachment param
  p_customer_id     UUID    DEFAULT NULL,   -- anon auth model
  p_attachment_urls TEXT[]  DEFAULT '{}'   -- new multi-image param
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_customer_id UUID;
  v_request     RECORD;
  v_urls        TEXT[];
BEGIN
  -- Resolve customer identity: prefer Supabase auth (admin / future migration),
  -- fall back to explicit p_customer_id (anon / dev_auth flow).
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_customer_id
      FROM customers
     WHERE auth_user_id = auth.uid()
       AND is_active = TRUE
     LIMIT 1;
  ELSIF p_customer_id IS NOT NULL THEN
    SELECT id INTO v_customer_id
      FROM customers
     WHERE id = p_customer_id
       AND is_active = TRUE
     LIMIT 1;
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated customer not found'
      USING ERRCODE = '42501';
  END IF;

  IF p_message IS NULL OR TRIM(p_message) = '' THEN
    RAISE EXCEPTION 'Message cannot be empty'
      USING ERRCODE = 'P0001';
  END IF;

  -- Validate request belongs to customer and is not closed.
  SELECT id, status INTO v_request
    FROM refund_requests
   WHERE id = p_request_id
     AND customer_id = v_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request not found or does not belong to this customer'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status = 'closed' THEN
    RAISE EXCEPTION 'Cannot send message on a closed refund request'
      USING ERRCODE = 'P0001';
  END IF;

  -- Build attachment_urls array.
  -- Merge legacy p_attachment_url (single) into array if provided.
  v_urls := COALESCE(p_attachment_urls, '{}');
  IF p_attachment_url IS NOT NULL AND TRIM(p_attachment_url) <> '' THEN
    v_urls := array_prepend(TRIM(p_attachment_url), v_urls);
  END IF;

  INSERT INTO refund_messages (
    refund_request_id,
    sender_type,
    sender_id,
    message,
    attachment_url,
    attachment_urls,
    is_internal
  ) VALUES (
    p_request_id,
    'customer',
    v_customer_id,
    TRIM(p_message),
    NULLIF(TRIM(COALESCE(p_attachment_url, '')), ''),
    v_urls,
    FALSE
  );
END;
$$;

GRANT EXECUTE ON FUNCTION customer_add_refund_message(UUID, TEXT, TEXT, UUID, TEXT[])
  TO anon, authenticated;
