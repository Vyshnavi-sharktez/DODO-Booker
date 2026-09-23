-- ─────────────────────────────────────────────────────────────────────────────
-- Refund Transactions
--
-- Each row records one actual refund attempt (money movement).  A single
-- refund_request may have multiple transactions (partial refunds, retries
-- after failure).  Failed attempts are retained for audit; they are never
-- deleted or overwritten.
--
-- Key invariant (enforced by admin_initiate_refund_transaction RPC):
--   SUM(amount WHERE status = 'completed')  ≤  refund_requests.amount_paid_snapshot
--
-- Approval (refund_requests.status ∈ {approved, partially_approved}) does NOT
-- create a transaction row.  Transactions are created ONLY by an explicit
-- Admin action (admin_initiate_refund_transaction).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS refund_transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_request_id UUID NOT NULL REFERENCES refund_requests(id),

  -- Amount being refunded in this single attempt.  Always positive.
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),

  -- Gateway used for this specific transaction.
  -- 'razorpay'        — online payment reversal via Razorpay refund API.
  -- 'manual'          — manually processed outside the system (e.g. bank transfer).
  -- 'cod_cash_return' — cash returned to customer in person.
  gateway TEXT NOT NULL
    CHECK (gateway IN ('razorpay', 'manual', 'cod_cash_return')),

  -- Razorpay refund ID (rfnd_…), populated after gateway call succeeds.
  -- UNIQUE ensures we never double-process the same gateway refund.
  gateway_refund_id TEXT UNIQUE,

  -- Raw gateway response payload stored for audit and dispute resolution.
  gateway_response JSONB,

  -- Transaction lifecycle.
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'completed', 'failed')),

  failure_reason TEXT,

  -- How the money is being returned.
  refund_method TEXT NOT NULL
    CHECK (refund_method IN (
      'original_payment_method',  -- reversed to the card/UPI used at checkout
      'manual',                   -- bank transfer or other manual method
      'cod_cash_return'           -- physical cash handed back
    )),

  -- The admin who explicitly initiated this transaction.  NOT NULL — every
  -- refund transaction must have an authorised human actor.
  initiated_by UUID NOT NULL REFERENCES auth.users(id),
  initiated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Set when status transitions to 'completed'.
  completed_at TIMESTAMPTZ,

  metadata   JSONB       NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_refund_transactions_request_id
  ON refund_transactions (refund_request_id);

CREATE INDEX IF NOT EXISTS idx_refund_transactions_status
  ON refund_transactions (status);

-- ── updated_at trigger ────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_refund_transactions_updated_at ON refund_transactions;
CREATE TRIGGER trg_refund_transactions_updated_at
  BEFORE UPDATE ON refund_transactions
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_subscription();

-- ── Sync processed_amount on refund_requests ──────────────────────────────────
-- After a transaction completes or fails, keep the denormalised
-- refund_requests.processed_amount in sync with the sum of completed rows.

CREATE OR REPLACE FUNCTION fn_sync_refund_processed_amount()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_total NUMERIC;
BEGIN
  SELECT COALESCE(SUM(amount), 0)
    INTO v_total
    FROM refund_transactions
   WHERE refund_request_id = COALESCE(NEW.refund_request_id, OLD.refund_request_id)
     AND status = 'completed';

  UPDATE refund_requests
     SET processed_amount = v_total,
         updated_at       = now()
   WHERE id = COALESCE(NEW.refund_request_id, OLD.refund_request_id);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_refund_processed_amount ON refund_transactions;
CREATE TRIGGER trg_sync_refund_processed_amount
  AFTER INSERT OR UPDATE OF status ON refund_transactions
  FOR EACH ROW EXECUTE FUNCTION fn_sync_refund_processed_amount();

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE refund_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_refund_transactions" ON refund_transactions;
CREATE POLICY "service_role_all_refund_transactions"
  ON refund_transactions FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "admin_all_refund_transactions" ON refund_transactions;
CREATE POLICY "admin_all_refund_transactions"
  ON refund_transactions FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

-- anon SELECT: future customer app can view transaction status.
DROP POLICY IF EXISTS "anon_select_refund_transactions" ON refund_transactions;
CREATE POLICY "anon_select_refund_transactions"
  ON refund_transactions FOR SELECT
  TO anon
  USING (true);
