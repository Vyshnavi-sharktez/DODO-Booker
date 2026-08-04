-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 1: Vendor Wallet Foundation
--
-- 1. wallet_transactions  — audit log for all wallet activity
-- 2. fn_sync_wallet_balance_to_vendors — keeps vendors.wallet_balance in sync
--    with vendor_wallets.balance (vendor_wallets is the source of truth)
-- 3. admin_top_up_vendor_wallet RPC — SECURITY DEFINER, safe write path
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. wallet_transactions
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id      UUID          NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  type           TEXT          NOT NULL
                                 CHECK (type IN ('top_up', 'commission', 'penalty', 'adjustment')),
  amount         NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  balance_after  NUMERIC(12,2) NOT NULL,
  reference_id   UUID,
  reference_type TEXT          CHECK (reference_type IN ('booking', 'manual')),
  description    TEXT,
  created_by     UUID          REFERENCES auth.users(id),
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;

-- Admin (authenticated): full CRUD.
CREATE POLICY "admin_all_wallet_transactions"
  ON wallet_transactions FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

-- Vendor app (anon): read-only; row filtering enforced in Flutter via
-- .eq('vendor_id', currentVendorId).
--
-- The vendor app uses a custom phone+OTP flow with no Supabase Auth session,
-- so auth.uid() is always NULL for vendor requests.  This matches the pattern
-- used by vendor_subscriptions, vendor_subscription_payments, and all other
-- vendor-readable tables.  Replace with a scoped policy when vendor auth
-- migrates to Supabase Auth.
CREATE POLICY "anon_read_wallet_transactions"
  ON wallet_transactions FOR SELECT
  TO anon
  USING (true);

-- 2. Sync trigger: vendor_wallets.available_balance → vendors.wallet_balance
--    Fires on every available_balance update so the denormalized column stays current.
CREATE OR REPLACE FUNCTION fn_sync_wallet_balance_to_vendors()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  UPDATE vendors SET wallet_balance = NEW.available_balance WHERE id = NEW.vendor_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_wallet_balance
  AFTER UPDATE OF available_balance ON vendor_wallets
  FOR EACH ROW
  EXECUTE FUNCTION fn_sync_wallet_balance_to_vendors();

-- 3. Admin top-up RPC
--    Atomically updates vendor_wallets.available_balance and inserts a wallet_transaction.
--    The sync trigger above propagates the new balance to vendors.wallet_balance.
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
