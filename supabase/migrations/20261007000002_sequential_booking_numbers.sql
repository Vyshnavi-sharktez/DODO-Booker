-- ─────────────────────────────────────────────────────────────────────────────
-- Sequential Human-Facing Booking Numbers (DODO100001, DODO100002...)
--
-- REQUIREMENTS:
-- 1. Keep bookings.id as UUID.
-- 2. Add/use booking_number as separate field formatted as DODO100001, DODO100002...
-- 3. Start from 100001 and generate numbers database/server-side using a PostgreSQL sequence.
-- 4. Enforce UNIQUE constraint/index on booking_number.
-- 5. Never reuse numbers on cancellation/deletion.
-- 6. Safely backfill existing bookings starting from DODO100001 in created_at ASC, id ASC order.
-- 7. Adapt existing implementation without creating duplicate columns, sequences, or triggers.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Create PostgreSQL sequence for sequential booking numbers starting at 100001
CREATE SEQUENCE IF NOT EXISTS booking_number_seq START WITH 100001 INCREMENT BY 1;

-- 2. Ensure booking_number column exists on bookings table
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS booking_number TEXT;

-- 3. Safely backfill existing bookings starting from DODO100001 in booking creation order (created_at ASC, id ASC)
WITH numbered_bookings AS (
  SELECT id,
         'DODO' || (100000 + ROW_NUMBER() OVER (ORDER BY created_at ASC, id ASC))::text AS new_booking_number
  FROM bookings
)
UPDATE bookings b
SET booking_number = nb.new_booking_number
FROM numbered_bookings nb
WHERE b.id = nb.id;

-- 4. Synchronize sequence generator so future inserts pick up after the highest assigned backfill value
SELECT setval(
  'booking_number_seq',
  COALESCE(
    (
      SELECT MAX(CAST(SUBSTRING(booking_number FROM 5) AS BIGINT))
      FROM bookings
      WHERE booking_number ~ '^DODO[0-9]+$'
    ),
    100000
  ) + 1,
  false
);

-- 5. Set default column expression and NOT NULL / UNIQUE constraints on booking_number
ALTER TABLE bookings ALTER COLUMN booking_number SET DEFAULT ('DODO' || nextval('booking_number_seq')::text);
ALTER TABLE bookings ALTER COLUMN booking_number SET NOT NULL;

ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_booking_number_key;
ALTER TABLE bookings ADD CONSTRAINT bookings_booking_number_key UNIQUE (booking_number);

-- 6. Create or replace trigger to guarantee database/server-side assignment even if null/empty string is passed
CREATE OR REPLACE FUNCTION set_booking_number()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.booking_number IS NULL OR TRIM(NEW.booking_number) = '' THEN
    NEW.booking_number := 'DODO' || nextval('booking_number_seq')::text;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_booking_number ON bookings;
CREATE TRIGGER trigger_set_booking_number
BEFORE INSERT ON bookings
FOR EACH ROW
EXECUTE FUNCTION set_booking_number();

-- 7. Update admin_search_bookings_by_ref RPC to handle DODO prefix searches seamlessly
CREATE OR REPLACE FUNCTION admin_search_bookings_by_ref(p_query TEXT)
RETURNS TABLE(id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_query TEXT;
  v_clean_query TEXT;
BEGIN
  PERFORM fn_assert_active_admin();

  v_query := TRIM(p_query);
  IF v_query = '' THEN
    RETURN;
  END IF;

  v_clean_query := v_query;
  IF UPPER(v_clean_query) LIKE 'DODO-%' THEN
    v_clean_query := SUBSTRING(v_clean_query FROM 6);
  ELSIF UPPER(v_clean_query) LIKE 'DODO%' THEN
    v_clean_query := SUBSTRING(v_clean_query FROM 5);
  ELSIF UPPER(v_clean_query) LIKE 'BK-%' THEN
    v_clean_query := SUBSTRING(v_clean_query FROM 4);
  END IF;

  RETURN QUERY
  SELECT DISTINCT b.id
  FROM   bookings b
  WHERE  b.booking_number ILIKE '%' || v_query || '%'
      OR b.booking_number ILIKE '%' || v_clean_query || '%'
      OR b.id::TEXT        ILIKE '%' || v_query || '%'
      OR b.id::TEXT        ILIKE '%' || v_clean_query || '%'
  ORDER  BY b.id
  LIMIT  10;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_search_bookings_by_ref(TEXT) TO authenticated;
