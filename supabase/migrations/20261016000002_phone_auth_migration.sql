-- Supabase Phone Auth migration for Customer App and Vendor App.
-- Adds DB support for Twilio-backed OTP auth replacing dev_auth / vendor_dev_auth.
-- Customer app: adds customers.profile_complete, backfills from dev_auth.
-- Vendor app:   adds vendors.auth_user_id for auth user linking.
-- RPCs: check_vendor_phone (pre-OTP gate), ensure_customer_linked, ensure_vendor_linked.

-- 1. Add profile_complete to customers (backfilled from dev_auth below)
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS profile_complete boolean NOT NULL DEFAULT false;

-- 2. Add auth_user_id to vendors for Supabase auth linking
ALTER TABLE public.vendors
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- 3. Backfill customers.profile_complete from dev_auth where phones match
UPDATE public.customers c
SET profile_complete = true
FROM public.dev_auth d
WHERE c.phone = d.phone
  AND d.profile_complete = true;

-- 4. check_vendor_phone: returns true if the phone belongs to a vendor or dodo_team member.
--    Called by the vendor app BEFORE sending an OTP to prevent spam and unregistered logins.
CREATE OR REPLACE FUNCTION public.check_vendor_phone(p_phone text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM vendors   WHERE phone = p_phone AND is_active = true
    UNION ALL
    SELECT 1 FROM dodo_teams WHERE phone = p_phone AND is_active = true
  );
$$;

REVOKE ALL ON FUNCTION public.check_vendor_phone(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_vendor_phone(text) TO anon;
GRANT EXECUTE ON FUNCTION public.check_vendor_phone(text) TO authenticated;

-- 5. ensure_customer_linked: links the calling auth user to their customer record.
--    Creates a new customer row if one doesn't exist for this phone.
--    Returns the customer UUID.
CREATE OR REPLACE FUNCTION public.ensure_customer_linked(p_phone text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_id    uuid;
  v_customer_id uuid;
BEGIN
  v_auth_id := auth.uid();
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id INTO v_customer_id
  FROM customers
  WHERE phone = p_phone
  LIMIT 1;

  IF v_customer_id IS NOT NULL THEN
    UPDATE customers SET auth_user_id = v_auth_id WHERE id = v_customer_id;
    RETURN v_customer_id;
  END IF;

  INSERT INTO customers (phone, full_name, email, is_active, auth_user_id)
  VALUES (p_phone, '', '', true, v_auth_id)
  RETURNING id INTO v_customer_id;

  RETURN v_customer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_customer_linked(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_customer_linked(text) TO authenticated;

-- 6. ensure_vendor_linked: links the calling auth user to their vendor row.
--    No-ops for dodo_team members (they don't have a vendors row).
--    Returns true if a vendor row was updated.
CREATE OR REPLACE FUNCTION public.ensure_vendor_linked(p_phone text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_id uuid;
BEGIN
  v_auth_id := auth.uid();
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE vendors SET auth_user_id = v_auth_id WHERE phone = p_phone;
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_vendor_linked(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_vendor_linked(text) TO authenticated;
