-- Vendors use the anon Supabase role (custom phone+OTP auth, auth.uid() is always
-- NULL), so the existing RLS policy "customer_questions: anon read answered"
-- silently hides pending questions from vendor queries.  A SECURITY DEFINER
-- function bypasses RLS and returns all questions for a given vendor_id,
-- consistent with the answer_customer_question_as_vendor pattern.

CREATE OR REPLACE FUNCTION fetch_vendor_questions(p_vendor_id UUID)
RETURNS SETOF customer_questions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM customer_questions
  WHERE vendor_id = p_vendor_id
  ORDER BY created_at DESC;
END;
$$;

NOTIFY pgrst, 'reload schema';
