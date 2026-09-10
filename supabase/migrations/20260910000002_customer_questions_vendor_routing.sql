-- Route customer questions for custom services to the owning vendor.
--
-- Changes:
-- 1. Add custom_service_id (nullable FK → vendor_service_requests) so questions
--    about custom services can be stored without a catalog_node service_id.
-- 2. Add vendor_id (nullable FK → vendors) so questions are routed to the
--    specific vendor who owns/provides the service.
-- 3. Make service_id nullable — custom service questions won't have one.
-- 4. Add check: exactly one of (service_id, custom_service_id) must be set.
-- 5. Add a SECURITY DEFINER RPC for vendor answering.
--    Vendors use the anon Supabase role (custom phone+OTP auth, no auth.uid()),
--    so a permissive anon UPDATE policy is not used; ownership is validated inside
--    the function instead.

ALTER TABLE customer_questions
  ADD COLUMN IF NOT EXISTS custom_service_id UUID
    REFERENCES vendor_service_requests(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS vendor_id UUID
    REFERENCES vendors(id) ON DELETE SET NULL;

ALTER TABLE customer_questions
  ALTER COLUMN service_id DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_cq_exactly_one_service'
      AND conrelid = 'customer_questions'::regclass
  ) THEN
    ALTER TABLE customer_questions
      ADD CONSTRAINT chk_cq_exactly_one_service
        CHECK (
          (service_id IS NOT NULL)::int + (custom_service_id IS NOT NULL)::int = 1
        );
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_customer_questions_custom_service_id
  ON customer_questions (custom_service_id);
CREATE INDEX IF NOT EXISTS idx_customer_questions_vendor_id
  ON customer_questions (vendor_id);

-- ── Vendor answer RPC ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION answer_customer_question_as_vendor(
  p_question_id UUID,
  p_vendor_id   UUID,
  p_answer      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q      customer_questions%ROWTYPE;
  v_name   TEXT;
  v_preview TEXT;
BEGIN
  SELECT * INTO v_q
  FROM customer_questions
  WHERE id = p_question_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Question not found: %', p_question_id;
  END IF;

  IF v_q.vendor_id IS DISTINCT FROM p_vendor_id THEN
    RAISE EXCEPTION 'Not authorised to answer this question';
  END IF;

  SELECT service_name INTO v_name
  FROM vendor_service_requests
  WHERE id = v_q.custom_service_id
  LIMIT 1;

  UPDATE customer_questions
  SET status      = 'answered',
      answer      = p_answer,
      answered_at = NOW()
  WHERE id = p_question_id;

  v_preview := CASE
    WHEN length(v_q.question) > 80
      THEN left(v_q.question, 80) || '…'
    ELSE v_q.question
  END;

  INSERT INTO notifications (
    user_type, user_id,
    title, message,
    notification_type, is_read,
    entity_type, entity_id,
    customer_question_id
  ) VALUES (
    'customer',
    v_q.customer_id,
    'Your question was answered',
    CASE
      WHEN v_name IS NOT NULL
        THEN 'Your question about ' || v_name || ': "' || v_preview || '" has been answered.'
      ELSE 'Your question "' || v_preview || '" has been answered.'
    END,
    'question_answered',
    false,
    'custom_service_question',
    v_q.custom_service_id,
    v_q.id
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
