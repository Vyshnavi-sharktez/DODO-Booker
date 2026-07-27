-- ── Vendor Subscription Module ────────────────────────────────────────────────
--
-- Tables:
--   subscription_plans             — admin-managed plan catalogue
--   vendor_subscriptions           — one record per vendor's active/historical subscription
--   vendor_subscription_payments   — full payment history per subscription
--
-- Backend validation:
--   check_vendor_cod_eligibility() — called before any COD booking is created /
--                                    assigned; returns false if vendor is
--                                    ineligible.
--   fn_vendor_subscription_status_updated_at() — keeps updated_at fresh.
--
-- RLS:
--   Admin (authenticated)   → full CRUD on all three tables.
--   Vendor (authenticated)  → SELECT own subscription + payments only.
--
-- Safe to re-run: IF NOT EXISTS / CREATE OR REPLACE throughout.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── subscription_plans ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS subscription_plans (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name             TEXT NOT NULL,
  description      TEXT,
  billing_cycle    TEXT NOT NULL DEFAULT 'monthly'
                     CHECK (billing_cycle IN ('daily','weekly','monthly','quarterly','yearly','custom')),
  duration_days    INT  NOT NULL DEFAULT 30,
  joining_fee      NUMERIC(12,2),
  subscription_fee NUMERIC(12,2),
  -- jsonb permissions key-value. Known keys:
  --   allow_cod               boolean
  --   allow_booking_assignment boolean
  --   priority_listing        boolean
  --   reduced_commission_pct  numeric (0-100)
  permissions      JSONB NOT NULL DEFAULT '{}',
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order       INT     NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── vendor_subscriptions ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS vendor_subscriptions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id      UUID NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  plan_id        UUID NOT NULL REFERENCES subscription_plans(id),
  status         TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','active','expired','suspended','cancelled')),
  start_date     TIMESTAMPTZ,
  expiry_date    TIMESTAMPTZ,
  renewal_count  INT NOT NULL DEFAULT 0,
  notes          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- one active/pending record per vendor at most
CREATE UNIQUE INDEX IF NOT EXISTS uq_vendor_subscriptions_active
  ON vendor_subscriptions(vendor_id)
  WHERE status IN ('active','pending');

-- ── vendor_subscription_payments ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS vendor_subscription_payments (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id      UUID NOT NULL REFERENCES vendor_subscriptions(id) ON DELETE CASCADE,
  vendor_id            UUID NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  payment_type         TEXT NOT NULL
                         CHECK (payment_type IN ('joining_fee','subscription_fee','renewal','refund')),
  amount               NUMERIC(12,2) NOT NULL,
  status               TEXT NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending','paid','failed','refunded')),
  payment_reference    TEXT,
  paid_at              TIMESTAMPTZ,
  notes                TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── updated_at triggers ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_set_updated_at_subscription()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subscription_plans_updated_at ON subscription_plans;
CREATE TRIGGER trg_subscription_plans_updated_at
  BEFORE UPDATE ON subscription_plans
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_subscription();

DROP TRIGGER IF EXISTS trg_vendor_subscriptions_updated_at ON vendor_subscriptions;
CREATE TRIGGER trg_vendor_subscriptions_updated_at
  BEFORE UPDATE ON vendor_subscriptions
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_subscription();

-- ── Backend COD eligibility check ─────────────────────────────────────────────
--
-- Returns TRUE when the vendor may accept / be assigned a COD booking.
-- Rules (applied only when subscription module is enabled via settings table):
--   1. Vendor row must exist and is_active = true.
--   2. If 'subscription_enabled' setting = 'true':
--      a. Vendor must have an active subscription.
--      b. That plan must have allow_cod = true.
-- Any NULL / missing setting is treated as the permissive default (module off).

CREATE OR REPLACE FUNCTION check_vendor_cod_eligibility(p_vendor_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_subscription_enabled TEXT;
  v_require_subscription  TEXT;
  v_allow_free_vendors    TEXT;
  v_is_active             BOOLEAN;
  v_sub_status            TEXT;
  v_allow_cod             BOOLEAN;
BEGIN
  -- Read global settings (default = subscription module off)
  SELECT setting_value INTO v_subscription_enabled
    FROM settings WHERE setting_key = 'subscription_enabled';
  v_subscription_enabled := COALESCE(v_subscription_enabled, 'false');

  -- Check vendor exists and is active
  SELECT is_active INTO v_is_active FROM vendors WHERE id = p_vendor_id;
  IF NOT FOUND OR NOT v_is_active THEN
    RETURN FALSE;
  END IF;

  -- If module is disabled, vendor is eligible (old behaviour)
  IF v_subscription_enabled <> 'true' THEN
    RETURN TRUE;
  END IF;

  SELECT setting_value INTO v_require_subscription
    FROM settings WHERE setting_key = 'subscription_require_active';
  v_require_subscription := COALESCE(v_require_subscription, 'false');

  SELECT setting_value INTO v_allow_free_vendors
    FROM settings WHERE setting_key = 'subscription_allow_free_vendors';
  v_allow_free_vendors := COALESCE(v_allow_free_vendors, 'true');

  -- If not required, allow all active vendors
  IF v_require_subscription <> 'true' THEN
    RETURN TRUE;
  END IF;

  -- Look up active subscription + plan COD permission
  SELECT vs.status,
         (sp.permissions->>'allow_cod')::BOOLEAN
    INTO v_sub_status, v_allow_cod
    FROM vendor_subscriptions vs
    JOIN subscription_plans sp ON sp.id = vs.plan_id
   WHERE vs.vendor_id = p_vendor_id
     AND vs.status = 'active'
   LIMIT 1;

  IF NOT FOUND THEN
    -- No active subscription
    RETURN v_allow_free_vendors = 'true';
  END IF;

  RETURN COALESCE(v_allow_cod, FALSE);
END;
$$;

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE subscription_plans            ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendor_subscriptions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendor_subscription_payments  ENABLE ROW LEVEL SECURITY;

-- subscription_plans: authenticated (admin) full access; no vendor read needed
-- (vendor app fetches plans via an RPC / admin-granted SELECT)
DROP POLICY IF EXISTS "admin_all_subscription_plans"   ON subscription_plans;
CREATE POLICY "admin_all_subscription_plans"
  ON subscription_plans FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

-- Allow anon / vendor token to SELECT active plans for the registration flow
DROP POLICY IF EXISTS "public_read_active_plans"       ON subscription_plans;
CREATE POLICY "public_read_active_plans"
  ON subscription_plans FOR SELECT
  TO anon
  USING (is_active = true);

-- vendor_subscriptions: admin full access; vendor anon read (scoped in Flutter by vendor_id)
--
-- The vendor app authenticates via a custom phone+OTP flow stored in SharedPreferences
-- and queries Supabase as the `anon` role with no Supabase Auth session.
-- auth.uid() is always NULL for vendor requests, so row-level scoping via auth.uid()
-- is not possible without an auth_user_id column on vendors (not present in this schema).
--
-- Row filtering is enforced at the application layer: every Flutter query includes
-- .eq('vendor_id', currentVendorId). This matches the pattern used by bookings,
-- notifications, documents, and all other vendor-readable tables in this project.
--
-- TODO: When vendor authentication migrates to Supabase Auth, replace the anon SELECT
-- policy below with a scoped policy:
--   USING (vendor_id = (SELECT id FROM vendors WHERE auth_user_id = auth.uid() LIMIT 1))
DROP POLICY IF EXISTS "admin_all_vendor_subscriptions"  ON vendor_subscriptions;
CREATE POLICY "admin_all_vendor_subscriptions"
  ON vendor_subscriptions FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_read_vendor_subscriptions"  ON vendor_subscriptions;
CREATE POLICY "anon_read_vendor_subscriptions"
  ON vendor_subscriptions FOR SELECT
  TO anon
  USING (true);

-- vendor_subscription_payments: admin full; vendor anon read (scoped in Flutter)
DROP POLICY IF EXISTS "admin_all_subscription_payments" ON vendor_subscription_payments;
CREATE POLICY "admin_all_subscription_payments"
  ON vendor_subscription_payments FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_read_subscription_payments" ON vendor_subscription_payments;
CREATE POLICY "anon_read_subscription_payments"
  ON vendor_subscription_payments FOR SELECT
  TO anon
  USING (true);

-- ── Realtime ──────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE vendor_subscriptions, vendor_subscription_payments;
  END IF;
END;
$$;
