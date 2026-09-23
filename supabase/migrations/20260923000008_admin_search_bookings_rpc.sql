-- ─────────────────────────────────────────────────────────────────────────────
-- admin_search_bookings_by_ref
--
-- Returns up to 10 booking IDs whose booking_number OR id (cast to text)
-- matches the given search term.  The Supabase Dart client cannot send
-- id::text in a PostgREST filter column (the cast is silently dropped,
-- producing "operator does not exist: uuid ~~ unknown").  Moving the cast
-- into a SQL function avoids the client limitation entirely.
--
-- The caller passes whatever the admin typed (last-5 digits, a BK- reference,
-- or a partial UUID).  This function strips the BK- prefix before comparing
-- against the UUID text, so all three forms match the same row.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_search_bookings_by_ref(p_query TEXT)
RETURNS TABLE(id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_query TEXT;
BEGIN
  PERFORM fn_assert_active_admin();

  v_query := TRIM(p_query);
  IF v_query = '' THEN
    RETURN;
  END IF;

  -- Strip BK- prefix so the admin can type either "B1C92" or "BK-C86B1C92".
  IF UPPER(v_query) LIKE 'BK-%' THEN
    v_query := SUBSTRING(v_query FROM 4);
  END IF;

  RETURN QUERY
  SELECT DISTINCT b.id
  FROM   bookings b
  WHERE  b.booking_number ILIKE '%' || v_query || '%'
      OR b.id::TEXT        ILIKE '%' || v_query || '%'
  ORDER  BY b.id
  LIMIT  10;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_search_bookings_by_ref(TEXT) TO authenticated;
