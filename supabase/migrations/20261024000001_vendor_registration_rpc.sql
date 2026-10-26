-- Phone Auth: ensure_vendor_created RPC for new vendor self-registration.
-- Called after OTP verification when the phone is not found in vendors or dodo_teams.
-- Also adds customers.auth_user_id guard (IF NOT EXISTS) in case it is absent from
-- the initial schema so ensure_customer_linked never fails on a fresh DB.

-- 1. Safe guard: customers.auth_user_id (initial schema should have this already)
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- 2. ensure_vendor_created:
--    • If a vendor row already exists for p_phone, links its auth_user_id and returns its id.
--    • Otherwise, inserts a minimal vendor record and returns the new id.
--    Requires an active Supabase Auth session (auth.uid() must be non-null).
--    SECURITY DEFINER bypasses the INSERT restriction on the vendors table.
CREATE OR REPLACE FUNCTION public.ensure_vendor_created(p_phone text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_id   uuid;
  v_vendor_id uuid;
BEGIN
  v_auth_id := auth.uid();
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Link and return existing vendor if found
  SELECT id INTO v_vendor_id FROM vendors WHERE phone = p_phone LIMIT 1;
  IF v_vendor_id IS NOT NULL THEN
    UPDATE vendors SET auth_user_id = v_auth_id WHERE id = v_vendor_id;
    RETURN v_vendor_id;
  END IF;

  -- Create a minimal vendor record for the new registrant
  INSERT INTO vendors (phone, business_name, is_active, wallet_balance, status, auth_user_id)
  VALUES (p_phone, '', true, 0, 'active', v_auth_id)
  RETURNING id INTO v_vendor_id;

  RETURN v_vendor_id;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_vendor_created(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_vendor_created(text) TO authenticated;
