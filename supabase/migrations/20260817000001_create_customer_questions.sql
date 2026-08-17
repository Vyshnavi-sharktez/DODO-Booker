CREATE TABLE IF NOT EXISTS customer_questions (
  id             UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  service_id     UUID        NOT NULL REFERENCES catalog_nodes(id) ON DELETE CASCADE,
  customer_id    UUID        NOT NULL,
  customer_name  TEXT,
  customer_phone TEXT,
  question       TEXT        NOT NULL,
  status         TEXT        NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'answered')),
  answer         TEXT,
  answered_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customer_questions_service_id
  ON customer_questions (service_id);
CREATE INDEX IF NOT EXISTS idx_customer_questions_customer_id
  ON customer_questions (customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_questions_status
  ON customer_questions (status);

ALTER TABLE customer_questions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customer_questions'
    AND policyname = 'customer_questions: anon read answered'
  ) THEN
    CREATE POLICY "customer_questions: anon read answered"
      ON customer_questions FOR SELECT TO anon
      USING (status = 'answered');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customer_questions'
    AND policyname = 'customer_questions: authenticated read all'
  ) THEN
    CREATE POLICY "customer_questions: authenticated read all"
      ON customer_questions FOR SELECT TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customer_questions'
    AND policyname = 'customer_questions: insert'
  ) THEN
    CREATE POLICY "customer_questions: insert"
      ON customer_questions FOR INSERT TO anon, authenticated
      WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customer_questions'
    AND policyname = 'customer_questions: authenticated update'
  ) THEN
    CREATE POLICY "customer_questions: authenticated update"
      ON customer_questions FOR UPDATE TO authenticated
      USING (true) WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customer_questions'
    AND policyname = 'customer_questions: authenticated delete'
  ) THEN
    CREATE POLICY "customer_questions: authenticated delete"
      ON customer_questions FOR DELETE TO authenticated
      USING (true);
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
