-- ─────────────────────────────────────────────────────────────────────────────
-- Upgrade wallet_transactions to the approved Vendor Wallet schema.
--
-- The table pre-existed with an older schema:
--   id, vendor_id, vendor_wallet_id, type, amount, description, booking_id,
--   created_at
--
-- Changes applied:
--   1. Add new columns: balance_after, reference_id, reference_type, created_by
--   2. Migrate booking_id → reference_id / reference_type = 'booking'
--   3. Normalise legacy type values to the new enum
--   4. Fix non-positive amounts so the amount > 0 constraint can be added
--   5. Replace existing type CHECK with the new enum
--   6. Add reference_type CHECK and amount > 0 CHECK
--   7. Drop superseded columns: vendor_wallet_id, booking_id
--   8. Add index used by the idempotency guard in Phase 2 trigger
--   9. Recreate admin_top_up_vendor_wallet RPC against the upgraded schema
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Add new columns ────────────────────────────────────────────────────────

-- balance_after: NOT NULL in the approved design.
-- Existing rows receive 0 as a sentinel; the default is dropped afterwards so
-- future inserts must supply an explicit value.
ALTER TABLE wallet_transactions
  ADD COLUMN IF NOT EXISTS balance_after  NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reference_id   UUID,
  ADD COLUMN IF NOT EXISTS reference_type TEXT,
  ADD COLUMN IF NOT EXISTS created_by     UUID REFERENCES auth.users(id);

ALTER TABLE wallet_transactions ALTER COLUMN balance_after DROP DEFAULT;

-- ── 2. Migrate booking_id → reference_id / reference_type ─────────────────────

UPDATE wallet_transactions
   SET reference_id   = booking_id,
       reference_type = 'booking'
 WHERE booking_id IS NOT NULL;

-- ── 3. Normalise legacy type values ──────────────────────────────────────────
-- Old TransactionType enum: credit | debit | withdrawal | settlement
-- New enum:                 top_up | commission | penalty  | adjustment

UPDATE wallet_transactions SET type = 'top_up'     WHERE type = 'credit';
UPDATE wallet_transactions SET type = 'adjustment'
 WHERE type NOT IN ('top_up', 'commission', 'penalty', 'adjustment');

-- ── 4. Fix non-positive amounts ───────────────────────────────────────────────
-- Old schema allowed negative amounts for debits; new design uses positive
-- amounts with type indicating direction.

UPDATE wallet_transactions SET amount = ABS(amount) WHERE amount < 0;
UPDATE wallet_transactions SET amount = 0.01        WHERE amount = 0;

-- ── 5. Replace existing type CHECK constraint ─────────────────────────────────
-- The constraint name is unknown (table was created outside migrations), so
-- find and drop it dynamically before adding the new one.

DO $$
DECLARE
  v_name TEXT;
BEGIN
  SELECT con.conname INTO v_name
    FROM pg_constraint con
    JOIN pg_class     rel ON rel.oid = con.conrelid
   WHERE rel.relname  = 'wallet_transactions'
     AND con.contype  = 'c'
     AND pg_get_constraintdef(con.oid) ILIKE '%type%'
   ORDER BY con.oid
   LIMIT 1;

  IF v_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE wallet_transactions DROP CONSTRAINT ' || quote_ident(v_name);
  END IF;
END $$;

ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check
    CHECK (type IN ('top_up', 'commission', 'penalty', 'adjustment'));

-- ── 6. Add reference_type CHECK and amount > 0 CHECK ─────────────────────────

ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_reference_type_check
    CHECK (reference_type IN ('booking', 'manual'));

ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_amount_positive
    CHECK (amount > 0);

-- ── 7. Drop superseded columns ────────────────────────────────────────────────
-- CASCADE drops any FK constraints on these columns automatically.

ALTER TABLE wallet_transactions DROP COLUMN IF EXISTS vendor_wallet_id CASCADE;
ALTER TABLE wallet_transactions DROP COLUMN IF EXISTS booking_id        CASCADE;

-- ── 8. Index for Phase 2 idempotency guard ────────────────────────────────────
-- fn_deduct_commission_on_booking_complete checks:
--   WHERE reference_id = NEW.id AND reference_type = 'booking' AND type = 'commission'

CREATE INDEX IF NOT EXISTS idx_wallet_txn_reference
  ON wallet_transactions (reference_id, reference_type, type)
  WHERE reference_id IS NOT NULL;

-- ── 9. Recreate admin_top_up_vendor_wallet against the upgraded schema ────────
-- Redefining here ensures the RPC and wallet_transactions always match after
-- this migration completes. The version in 00002 used late binding and would
-- only fail at call time if columns were absent; this removes that ambiguity.

CREATE OR REPLACE FUNCTION admin_top_up_vendor_wallet(
  p_vendor_id   UUID,
  p_amount      NUMERIC,
  p_description TEXT  DEFAULT NULL,
  p_admin_id    UUID  DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_new_balance    NUMERIC;
  v_transaction_id UUID;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Top-up amount must be positive';
  END IF;

  UPDATE vendor_wallets
     SET available_balance = available_balance + p_amount,
         updated_at        = now()
   WHERE vendor_id = p_vendor_id
  RETURNING available_balance INTO v_new_balance;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Wallet not found for vendor %', p_vendor_id;
  END IF;

  INSERT INTO wallet_transactions (
    vendor_id, type, amount, balance_after,
    reference_type, description, created_by
  ) VALUES (
    p_vendor_id, 'top_up', p_amount, v_new_balance,
    'manual', p_description, p_admin_id
  )
  RETURNING id INTO v_transaction_id;

  RETURN v_transaction_id;
END;
$$;
