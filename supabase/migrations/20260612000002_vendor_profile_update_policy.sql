-- Allow vendor app (anon) to update vendor records.
-- The app enforces phone-scoped updates at the repository layer.
ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'vendors'
      AND policyname = 'anon_update_vendors'
  ) THEN
    CREATE POLICY "anon_update_vendors" ON vendors
      FOR UPDATE TO anon
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
