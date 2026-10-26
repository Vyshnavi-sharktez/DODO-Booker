-- ─────────────────────────────────────────────────────────────────────────────
-- Sequential Human-Facing Customer IDs (CUST0001, CUST0002...)
--
-- Mirrors the booking_number_seq / trigger approach used for booking numbers.
-- REQUIREMENTS:
-- 1. Keep customers.id as UUID (unchanged).
-- 2. Add customer_number TEXT as a separate human-facing identifier.
-- 3. Format: CUST0001, CUST0002, … (4-digit zero-padded, extends naturally).
-- 4. Use a PostgreSQL sequence for concurrent-safe, duplicate-free generation.
-- 5. Enforce UNIQUE + NOT NULL constraints.
-- 6. Safely backfill all existing customers in created_at ASC, id ASC order.
-- 7. Trigger guarantees DB-side assignment even if caller passes NULL/empty.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Create sequence starting at 1
CREATE SEQUENCE IF NOT EXISTS customer_number_seq START WITH 1 INCREMENT BY 1;

-- 2. Add column (nullable initially so backfill can run first)
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS customer_number TEXT;

-- 3. Backfill existing rows in creation order
WITH numbered AS (
  SELECT id,
         'CUST' || LPAD(
           ROW_NUMBER() OVER (ORDER BY created_at ASC, id ASC)::TEXT,
           4, '0'
         ) AS cn
  FROM customers
)
UPDATE customers c
SET customer_number = n.cn
FROM numbered n
WHERE c.id = n.id;

-- 4. Advance sequence past the highest backfilled value so new inserts
--    continue from the correct next number.
SELECT setval(
  'customer_number_seq',
  COALESCE(
    (SELECT MAX(CAST(SUBSTRING(customer_number FROM 5) AS BIGINT))
     FROM customers
     WHERE customer_number ~ '^CUST[0-9]+$'),
    0
  ) + 1,
  false   -- is_called = false → next nextval() returns this exact value
);

-- 5. Set column DEFAULT, NOT NULL, and UNIQUE
ALTER TABLE public.customers
  ALTER COLUMN customer_number
    SET DEFAULT ('CUST' || LPAD(nextval('customer_number_seq')::TEXT, 4, '0'));

ALTER TABLE public.customers ALTER COLUMN customer_number SET NOT NULL;

ALTER TABLE public.customers
  DROP CONSTRAINT IF EXISTS customers_customer_number_key;
ALTER TABLE public.customers
  ADD CONSTRAINT customers_customer_number_key UNIQUE (customer_number);

-- 6. Trigger: guarantee DB-side generation even when caller passes NULL/empty
CREATE OR REPLACE FUNCTION set_customer_number()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.customer_number IS NULL OR TRIM(NEW.customer_number) = '' THEN
    NEW.customer_number :=
      'CUST' || LPAD(nextval('customer_number_seq')::TEXT, 4, '0');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_customer_number ON public.customers;
CREATE TRIGGER trigger_set_customer_number
  BEFORE INSERT ON public.customers
  FOR EACH ROW EXECUTE FUNCTION set_customer_number();
