-- cart_items: replace auth.uid()-based policies with anon-compatible policies.
--
-- WHY: The customer app uses phone/OTP auth stored in SharedPreferences.
-- It calls Supabase with the anon key and no Supabase Auth session, so
-- auth.uid() is always NULL and auth-based policies always reject writes.
--
-- TEMPORARY: These open policies unblock cart sync until the app migrates
-- to a real Supabase Auth session (phone OTP via signInWithOtp).

-- ── Drop all existing policies on cart_items ──────────────────────────────────

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'cart_items'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.cart_items', r.policyname);
  END LOOP;
END
$$;

-- ── New policies: anon role (unauthenticated Supabase client) ─────────────────

-- SELECT: allow reading own cart rows (anon can read any row — scoped by
-- customer_id in application code)
CREATE POLICY "anon_select_cart_items"
  ON public.cart_items
  FOR SELECT
  TO anon
  USING (true);

-- INSERT: allow anon to insert cart rows
CREATE POLICY "anon_insert_cart_items"
  ON public.cart_items
  FOR INSERT
  TO anon
  WITH CHECK (true);

-- UPDATE: allow anon to update cart rows
CREATE POLICY "anon_update_cart_items"
  ON public.cart_items
  FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);

-- DELETE: allow anon to delete cart rows
CREATE POLICY "anon_delete_cart_items"
  ON public.cart_items
  FOR DELETE
  TO anon
  USING (true);

-- ── Confirm RLS is still enabled ──────────────────────────────────────────────

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
