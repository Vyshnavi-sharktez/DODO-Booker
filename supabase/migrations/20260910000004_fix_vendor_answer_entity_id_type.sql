-- Fix: entity_id in notifications is UUID, not TEXT.
-- The original answer_customer_question_as_vendor RPC cast
-- v_q.custom_service_id to TEXT before inserting into entity_id (UUID column),
-- causing "column entity_id is of type uuid but expression is of type text".

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
