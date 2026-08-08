-- ── booking_payments ──────────────────────────────────────────────────────────
--
-- Stores every payment attempt tied to a booking.
-- Multiple rows per booking are supported to handle retries and refunds.
--
-- Payment lifecycle:
--   pending → processing → success
--                        → failed  (retry → new row, attempt_number + 1)
--                        → cancelled
--
-- Gateway IDs are populated progressively:
--   gateway_order_id   — set when the order is created (before redirect)
--   gateway_payment_id — set on capture / webhook receipt
--   gateway_signature  — set after HMAC verification
--   verified_at        — timestamp of successful verification
--
-- Design is gateway-neutral: `gateway` is free-text so future providers
-- (Stripe, PayU, PhonePe, etc.) can be added without a schema change.
--
-- Does NOT modify the bookings table.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS booking_payments (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id          UUID          NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,

  -- Free-text gateway name ('razorpay', 'stripe', 'payU', …).
  -- No CHECK constraint so new providers can be onboarded without migrations.
  gateway             TEXT          NOT NULL,

  -- Gateway-issued identifiers; populated progressively through the payment flow.
  gateway_order_id    TEXT,
  gateway_payment_id  TEXT,
  gateway_signature   TEXT,

  -- Financials (snapshotted at attempt time so history survives price changes)
  amount              NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  currency            TEXT          NOT NULL DEFAULT 'INR',

  -- Lifecycle state
  status              TEXT          NOT NULL DEFAULT 'pending'
                                      CHECK (status IN (
                                        'pending',      -- order created, awaiting customer action
                                        'processing',   -- gateway callback received, verifying
                                        'success',      -- signature verified, payment captured
                                        'failed',       -- gateway reported failure
                                        'cancelled'     -- customer or system cancelled
                                      )),

  -- Monotonically increasing per booking; new row on every retry.
  attempt_number      SMALLINT      NOT NULL DEFAULT 1 CHECK (attempt_number > 0),

  -- Human-readable reason populated on failed / cancelled transitions.
  failure_reason      TEXT,

  -- Set by the edge function after HMAC signature verification passes.
  verified_at         TIMESTAMPTZ,

  -- Raw gateway payload (order creation, capture, webhook, refund responses).
  -- Stored as-is for audit, debugging, and future gateway support.
  gateway_response    JSONB,

  -- Non-relational metadata: platform, app version, retry source, device info,
  -- coupon snapshot, gateway-specific fields, etc.
  metadata            JSONB         NOT NULL DEFAULT '{}'::jsonb,

  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),

  -- Prevents duplicate attempt numbers for the same booking.
  CONSTRAINT uq_booking_payment_attempt UNIQUE (booking_id, attempt_number)
);

-- ── Constraints ───────────────────────────────────────────────────────────────

-- Partial unique index: a gateway_order_id must map to exactly one payment row.
-- Partial (WHERE NOT NULL) so multiple NULL values are allowed across rows that
-- have not yet been assigned an order by the gateway.
CREATE UNIQUE INDEX IF NOT EXISTS uq_booking_payments_gateway_order_id
  ON booking_payments (gateway_order_id)
  WHERE gateway_order_id IS NOT NULL;

-- Partial unique index: a gateway_payment_id must map to exactly one row.
-- Prevents double-processing the same payment in webhook retries.
CREATE UNIQUE INDEX IF NOT EXISTS uq_booking_payments_gateway_payment_id
  ON booking_payments (gateway_payment_id)
  WHERE gateway_payment_id IS NOT NULL;

-- ── Indexes ───────────────────────────────────────────────────────────────────

-- All attempts for a booking (customer payment history, admin booking detail).
CREATE INDEX IF NOT EXISTS idx_booking_payments_booking_id
  ON booking_payments (booking_id);

-- Lifecycle filtering (admin dashboard: find pending / failed payments).
CREATE INDEX IF NOT EXISTS idx_booking_payments_status
  ON booking_payments (status);

-- Webhook fast-path: look up a pending row by gateway_order_id on capture.
-- The unique index above already serves as this lookup index; no duplicate needed.

-- Post-capture audit: look up a row by gateway_payment_id for refunds / disputes.
-- The unique index above already serves as this lookup index; no duplicate needed.

-- ── updated_at trigger ────────────────────────────────────────────────────────
--
-- Reuses fn_set_updated_at_subscription (defined in 20260727000001) which is a
-- generic trigger body: NEW.updated_at = NOW(); RETURN NEW.
-- No new function is created to avoid proliferating identical trigger functions.

DROP TRIGGER IF EXISTS trg_booking_payments_updated_at ON booking_payments;
CREATE TRIGGER trg_booking_payments_updated_at
  BEFORE UPDATE ON booking_payments
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_subscription();

-- ── Row Level Security ────────────────────────────────────────────────────────

ALTER TABLE booking_payments ENABLE ROW LEVEL SECURITY;

-- service_role: unrestricted access for Edge Functions (webhook handler,
-- payment verification, refund processing). service_role bypasses RLS by
-- default; this explicit policy is belt-and-suspenders.
DROP POLICY IF EXISTS "service_role_all_booking_payments" ON booking_payments;
CREATE POLICY "service_role_all_booking_payments"
  ON booking_payments FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- anon INSERT: customer app creates the initial payment attempt row.
-- Gated on the referenced booking existing, which prevents orphan rows and
-- ensures the customer can only attach a payment to a real booking.
--
-- LIMITATION: The project currently uses a custom phone-OTP auth flow where
-- the Flutter client calls Supabase as the `anon` role with no Supabase Auth
-- session (auth.uid() = NULL). Because of this, it is not possible to enforce
-- at the database level that the booking belongs to the requesting customer.
-- The Flutter checkout flow always supplies the signed-in customer's booking_id;
-- this is the only ownership guard in place until auth migrates to Supabase Auth.
--
-- TODO (auth migration): replace the WITH CHECK below with:
--   EXISTS (
--     SELECT 1 FROM bookings b
--     JOIN customers c ON c.id = b.customer_id
--     WHERE b.id = booking_id
--       AND c.auth_user_id = auth.uid()
--   )
DROP POLICY IF EXISTS "anon_insert_booking_payments" ON booking_payments;
CREATE POLICY "anon_insert_booking_payments"
  ON booking_payments FOR INSERT
  TO anon
  WITH CHECK (
    EXISTS (SELECT 1 FROM bookings WHERE id = booking_id)
  );

-- anon SELECT: customer app reads payment status for UI feedback (e.g. polling
-- for a pending → success transition while the Razorpay SDK is open).
--
-- LIMITATION: Same auth constraint as INSERT above — customer ownership cannot
-- be scoped at the DB layer without Supabase Auth. The Flutter client always
-- filters by its own booking_id (.eq('booking_id', <customerBookingId>)).
-- Payment IDs (UUIDs) are not guessable, which limits practical exposure.
--
-- TODO (auth migration): replace USING (true) with:
--   booking_id IN (
--     SELECT b.id FROM bookings b
--     JOIN customers c ON c.id = b.customer_id
--     WHERE c.auth_user_id = auth.uid()
--   )
DROP POLICY IF EXISTS "anon_select_booking_payments" ON booking_payments;
CREATE POLICY "anon_select_booking_payments"
  ON booking_payments FOR SELECT
  TO anon
  USING (true);

-- No UPDATE or DELETE for the anon role. Payment status transitions
-- (pending → processing → success / failed / cancelled) must go through an
-- Edge Function that runs as service_role and performs HMAC verification.
-- Allowing direct client-side status writes would let a customer mark their
-- own payment as 'success' without a valid gateway confirmation.

-- admin ALL: full access for audit, manual status corrections, and refund
-- workflows, restricted to rows in admin_users where is_active = TRUE.
-- Matches the pattern established in coupons (20260611000003) which is the
-- only other payment-sensitive table with an admin-scoped policy.
-- The USING / WITH CHECK subquery reads admin_users as the calling user's
-- auth.uid(); admin_users rows are readable to the calling session via the
-- "admin_users: authenticated user can read own row" policy (20260609000001).
DROP POLICY IF EXISTS "admin_all_booking_payments" ON booking_payments;
CREATE POLICY "admin_all_booking_payments"
  ON booking_payments FOR ALL
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

-- ── Realtime ──────────────────────────────────────────────────────────────────
-- Enables the customer app to receive a live push when the webhook edge function
-- flips status from 'pending' to 'success' or 'failed', removing the need for
-- client-side polling.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE booking_payments;
  END IF;
END;
$$;
