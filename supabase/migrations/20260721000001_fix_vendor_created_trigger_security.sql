-- fn_on_vendor_created fires AFTER INSERT ON vendors and creates the matching
-- vendor_wallets and vendor_settings rows.
--
-- The function was created as SECURITY INVOKER (the default), which means it
-- runs as the calling role (`authenticated` for the admin app).  vendor_wallets
-- has RLS enabled with only a SELECT policy for authenticated — no INSERT
-- policy — so the trigger was blocked for every vendor creation path: both
-- the Add Vendor form and Bulk Upload.
--
-- Fix: recreate the function as SECURITY DEFINER so it executes as its owner
-- (`postgres`), which bypasses RLS for the internal housekeeping writes.
-- This does NOT weaken RLS on vendor_wallets: authenticated users still have
-- SELECT access only.  The trigger is the sole controlled creation path.
-- SET search_path = public guards against search_path-injection attacks,
-- which is required practice for SECURITY DEFINER functions in Supabase.

CREATE OR REPLACE FUNCTION public.fn_on_vendor_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
    INSERT INTO vendor_wallets (vendor_id) VALUES (NEW.id)
    ON CONFLICT (vendor_id) DO NOTHING;
    INSERT INTO vendor_settings (vendor_id) VALUES (NEW.id)
    ON CONFLICT (vendor_id) DO NOTHING;
    RETURN NEW;
END;
$function$;
