-- ─────────────────────────────────────────────────────────────────────────────
-- Vendor Wallet Razorpay Top-Up Payments
--
-- 1. Extend wallet_transactions.reference_type to accept 'razorpay_topup'
-- 2. vendor_wallet_topup_attempts — tracks Razorpay order/payment state per
--    top-up; enables idempotency and prevents double-crediting
-- 3. complete_vendor_wallet_topup — atomically credits wallet after verified
--    payment; service_role only; idempotent on repeat calls
-- 4. fail_vendor_wallet_topup — marks attempt failed; never reverts a success
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Extend wallet_transactions.reference_type
--    The original CHECK only allows 'booking' and 'manual'. Adding 'razorpay_topup'
--    so Edge-Function-initiated top-ups can be distinguished from admin manual ones.

ALTER TABLE wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_reference_type_check;

ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_reference_type_check
    CHECK (reference_type IN ('booking', 'manual', 'razorpay_topup'));

-- 2. vendor_wallet_topup_attempts
CREATE TABLE IF NOT EXISTS vendor_wallet_topup_attempts (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id             UUID          NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  amount                NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  gateway               TEXT          NOT NULL DEFAULT 'razorpay',
  gateway_order_id      TEXT          UNIQUE,
  gateway_payment_id    TEXT,
  gateway_signature     TEXT,
  status                TEXT          NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'success', 'failed', 'cancelled')),
  wallet_transaction_id UUID          REFERENCES wallet_transactions(id),
  failure_reason        TEXT,
  gateway_response      JSONB,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  verified_at           TIMESTAMPTZ,
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Partial unique index: prevents two attempts ever sharing a gateway_payment_id
-- (i.e., one Razorpay payment crediting the wallet twice).
CREATE UNIQUE INDEX IF NOT EXISTS idx_vwta_gateway_payment_id
  ON vendor_wallet_topup_attempts (gateway_payment_id)
  WHERE gateway_payment_id IS NOT NULL;

-- Indexed for fast gateway_order_id lookup in the webhook handler.
CREATE INDEX IF NOT EXISTS idx_vwta_gateway_order_id
  ON vendor_wallet_topup_attempts (gateway_order_id)
  WHERE gateway_order_id IS NOT NULL;

ALTER TABLE vendor_wallet_topup_attempts ENABLE ROW LEVEL SECURITY;

-- Edge Functions (service_role): unrestricted.
CREATE POLICY "service_role_all_vendor_wallet_topup_attempts"
  ON vendor_wallet_topup_attempts FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

-- Admin (authenticated): full CRUD for audit visibility.
CREATE POLICY "admin_all_vendor_wallet_topup_attempts"
  ON vendor_wallet_topup_attempts FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

-- Vendor app (anon): read-only; row-level filtering via Flutter .eq('vendor_id', …).
CREATE POLICY "anon_read_vendor_wallet_topup_attempts"
  ON vendor_wallet_topup_attempts FOR SELECT
  TO anon
  USING (true);

-- 3. complete_vendor_wallet_topup
--
-- Called by verify-vendor-wallet-topup and razorpay-webhook after successful
-- payment. Atomically:
--   a) marks the attempt 'success'
--   b) credits vendor_wallets.available_balance
--   c) inserts a wallet_transactions ledger row
--   d) sends a vendor notification
--
-- Return values:
--   'completed'      — wallet credited this call
--   'already_complete' — idempotent: was already credited; no DB mutation
--
-- Raises SQLSTATE P0002 if attempt is not found.
-- Raises SQLSTATE 22000 for vendor_id mismatch or invalid state transition.
--
-- SECURITY: GRANTED to service_role only; anon/authenticated cannot call it.

CREATE OR REPLACE FUNCTION complete_vendor_wallet_topup(
  p_topup_attempt_id   UUID,
  p_vendor_id          UUID,
  p_gateway_payment_id TEXT,
  p_gateway_signature  TEXT,
  p_gateway_response   JSONB DEFAULT NULL
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_attempt            vendor_wallet_topup_attempts%ROWTYPE;
  v_new_balance        NUMERIC;
  v_transaction_id     UUID;
BEGIN
  -- Lock the row to serialize concurrent calls (webhook vs. verify function race).
  SELECT * INTO v_attempt
  FROM   vendor_wallet_topup_attempts
  WHERE  id = p_topup_attempt_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Top-up attempt not found' USING ERRCODE = 'P0002';
  END IF;

  -- Ensure the caller owns this attempt (prevents one vendor completing another's).
  IF v_attempt.vendor_id != p_vendor_id THEN
    RAISE EXCEPTION 'vendor_id mismatch for attempt %', p_topup_attempt_id
      USING ERRCODE = '22000';
  END IF;

  -- Idempotency: already credited — return without mutating anything.
  IF v_attempt.status = 'success' THEN
    RETURN 'already_complete';
  END IF;

  -- Only pending attempts may be completed; failed/cancelled cannot be resurrected.
  IF v_attempt.status != 'pending' THEN
    RAISE EXCEPTION 'Cannot complete attempt in status %', v_attempt.status
      USING ERRCODE = '22000';
  END IF;

  -- Mark attempt as successful before crediting to make the operation
  -- idempotent under retries even if the subsequent UPDATE or INSERT is slow.
  UPDATE vendor_wallet_topup_attempts
  SET    status              = 'success',
         gateway_payment_id  = p_gateway_payment_id,
         gateway_signature   = p_gateway_signature,
         gateway_response    = COALESCE(p_gateway_response, gateway_response),
         verified_at         = now(),
         updated_at          = now()
  WHERE  id = p_topup_attempt_id;

  -- Ensure vendor_wallets row exists (idempotent upsert).
  INSERT INTO vendor_wallets (vendor_id, available_balance)
  VALUES  (p_vendor_id, 0)
  ON CONFLICT (vendor_id) DO NOTHING;

  -- Credit the wallet (sync trigger propagates to vendors.wallet_balance).
  UPDATE vendor_wallets
  SET    available_balance = available_balance + v_attempt.amount,
         updated_at        = now()
  WHERE  vendor_id = p_vendor_id
  RETURNING available_balance INTO v_new_balance;

  -- Ledger entry — reference_type 'razorpay_topup' distinguishes from admin
  -- manual top-ups (reference_type 'manual').
  INSERT INTO wallet_transactions (
    vendor_id, type, amount, balance_after,
    reference_id, reference_type, description
  ) VALUES (
    p_vendor_id, 'top_up', v_attempt.amount, v_new_balance,
    p_topup_attempt_id, 'razorpay_topup',
    'Wallet Top-Up via Razorpay'
  )
  RETURNING id INTO v_transaction_id;

  -- Back-link the ledger row to the attempt.
  UPDATE vendor_wallet_topup_attempts
  SET    wallet_transaction_id = v_transaction_id
  WHERE  id = p_topup_attempt_id;

  -- In-app notification for the vendor.
  INSERT INTO notifications (
    user_type, user_id, title, message, notification_type,
    entity_type, entity_id, is_read, created_at
  ) VALUES (
    'vendor', p_vendor_id,
    'Wallet Top-Up Successful',
    'Your wallet has been credited with ₹' ||
      TRIM(TO_CHAR(v_attempt.amount, '999999990.00')) ||
      '. New balance: ₹' ||
      TRIM(TO_CHAR(v_new_balance, '999999990.00')) || '.',
    'wallet_alert', 'vendor_wallet', v_transaction_id, false, now()
  );

  RETURN 'completed';
END;
$$;

REVOKE ALL ON FUNCTION complete_vendor_wallet_topup(UUID, UUID, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION complete_vendor_wallet_topup(UUID, UUID, TEXT, TEXT, JSONB)
  TO service_role;

-- 4. fail_vendor_wallet_topup
--
-- Called when payment fails or is cancelled. Marks the attempt 'failed'.
-- A 'success' attempt is immutable — this function never reverts a credit.
--
-- Return values:
--   'failed'         — transitioned this call
--   'already_failed' — idempotent
--   'already_complete' — success rows are immutable; logged but not changed

CREATE OR REPLACE FUNCTION fail_vendor_wallet_topup(
  p_topup_attempt_id UUID,
  p_failure_reason   TEXT  DEFAULT NULL,
  p_gateway_response JSONB DEFAULT NULL
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_attempt vendor_wallet_topup_attempts%ROWTYPE;
BEGIN
  SELECT * INTO v_attempt
  FROM   vendor_wallet_topup_attempts
  WHERE  id = p_topup_attempt_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Top-up attempt not found' USING ERRCODE = 'P0002';
  END IF;

  -- A confirmed success is immutable.
  IF v_attempt.status = 'success' THEN
    RETURN 'already_complete';
  END IF;

  IF v_attempt.status = 'failed' THEN
    RETURN 'already_failed';
  END IF;

  UPDATE vendor_wallet_topup_attempts
  SET    status           = 'failed',
         failure_reason   = COALESCE(p_failure_reason, failure_reason),
         gateway_response = COALESCE(p_gateway_response, gateway_response),
         updated_at       = now()
  WHERE  id = p_topup_attempt_id;

  RETURN 'failed';
END;
$$;

REVOKE ALL ON FUNCTION fail_vendor_wallet_topup(UUID, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION fail_vendor_wallet_topup(UUID, TEXT, JSONB)
  TO service_role;
