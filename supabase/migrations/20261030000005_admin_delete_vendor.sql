-- admin_delete_vendor(p_vendor_id UUID)
--
-- SECURITY DEFINER RPC so the delete bypasses RLS entirely.
-- fn_assert_active_admin() still gates the call to authenticated admins.
-- All child tables use ON DELETE CASCADE or ON DELETE SET NULL so the
-- single DELETE statement is sufficient.

DROP FUNCTION IF EXISTS public.admin_delete_vendor(UUID);

CREATE OR REPLACE FUNCTION public.admin_delete_vendor(p_vendor_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_assert_active_admin();

  DELETE FROM vendors WHERE id = p_vendor_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vendor % not found', p_vendor_id
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_vendor(UUID) TO authenticated;
