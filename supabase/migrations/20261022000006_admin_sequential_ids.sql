-- ============================================================
-- Admin sequential IDs: ADM0001, ADM0002, …
-- Mirrors the customer_number_seq / vendor_number_seq pattern.
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS admin_number_seq
  START WITH 1
  INCREMENT BY 1
  NO MINVALUE
  NO MAXVALUE
  CACHE 1;

ALTER TABLE admin_users
  ADD COLUMN IF NOT EXISTS admin_number TEXT;

-- Backfill existing admin users in creation order
WITH ranked AS (
  SELECT id,
         'ADM' || LPAD(ROW_NUMBER() OVER (ORDER BY created_at ASC, id ASC)::TEXT, 4, '0') AS anum
  FROM admin_users
)
UPDATE admin_users a
SET admin_number = r.anum
FROM ranked r
WHERE a.id = r.id;

-- Advance sequence past the highest backfilled value so the next INSERT
-- does not collide with any backfilled number.
-- Use is_called=false so nextval() returns this value exactly
-- (matches customer_number_seq pattern). The +1/COALESCE,0 ensures
-- the value is ≥1 even on an empty table (avoids MINVALUE violation).
SELECT setval(
  'admin_number_seq',
  COALESCE(
    (SELECT MAX(SUBSTRING(admin_number FROM 4)::INTEGER)
     FROM admin_users
     WHERE admin_number IS NOT NULL),
    0
  ) + 1,
  false
);

ALTER TABLE admin_users
  ALTER COLUMN admin_number SET DEFAULT 'ADM' || LPAD(nextval('admin_number_seq')::TEXT, 4, '0'),
  ALTER COLUMN admin_number SET NOT NULL,
  ADD CONSTRAINT admin_users_admin_number_unique UNIQUE (admin_number);

-- Trigger ensures the number is assigned even when caller omits it.
-- This covers edge-function inserts and any direct inserts that skip
-- the DEFAULT (e.g. INSERT … ON CONFLICT DO NOTHING patterns).
CREATE OR REPLACE FUNCTION set_admin_number()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.admin_number IS NULL THEN
    NEW.admin_number := 'ADM' || LPAD(nextval('admin_number_seq')::TEXT, 4, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_set_admin_number ON admin_users;
CREATE TRIGGER trigger_set_admin_number
  BEFORE INSERT ON admin_users
  FOR EACH ROW
  EXECUTE FUNCTION set_admin_number();
