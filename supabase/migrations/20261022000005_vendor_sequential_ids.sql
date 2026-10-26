-- ============================================================
-- Vendor sequential IDs: VEN0001, VEN0002, …
-- Mirrors the customer_number_seq / trigger pattern.
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS vendor_number_seq
  START WITH 1
  INCREMENT BY 1
  NO MINVALUE
  NO MAXVALUE
  CACHE 1;

ALTER TABLE vendors
  ADD COLUMN IF NOT EXISTS vendor_number TEXT;

-- Backfill existing vendors in creation order
WITH ranked AS (
  SELECT id,
         'VEN' || LPAD(ROW_NUMBER() OVER (ORDER BY created_at ASC, id ASC)::TEXT, 4, '0') AS vnum
  FROM vendors
)
UPDATE vendors v
SET vendor_number = r.vnum
FROM ranked r
WHERE v.id = r.id;

-- Advance sequence past the highest backfilled value so next INSERT
-- does not collide with any backfilled number.
-- Use is_called=false so nextval() returns this value exactly
-- (matches customer_number_seq pattern). The +1/COALESCE,0 ensures
-- the value is ≥1 even on an empty table (avoids MINVALUE violation).
SELECT setval(
  'vendor_number_seq',
  COALESCE(
    (SELECT MAX(SUBSTRING(vendor_number FROM 4)::INTEGER)
     FROM vendors
     WHERE vendor_number IS NOT NULL),
    0
  ) + 1,
  false
);

ALTER TABLE vendors
  ALTER COLUMN vendor_number SET DEFAULT 'VEN' || LPAD(nextval('vendor_number_seq')::TEXT, 4, '0'),
  ALTER COLUMN vendor_number SET NOT NULL,
  ADD CONSTRAINT vendors_vendor_number_unique UNIQUE (vendor_number);

-- Trigger ensures the number is assigned even when caller omits it.
CREATE OR REPLACE FUNCTION set_vendor_number()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.vendor_number IS NULL THEN
    NEW.vendor_number := 'VEN' || LPAD(nextval('vendor_number_seq')::TEXT, 4, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_set_vendor_number ON vendors;
CREATE TRIGGER trigger_set_vendor_number
  BEFORE INSERT ON vendors
  FOR EACH ROW
  EXECUTE FUNCTION set_vendor_number();
