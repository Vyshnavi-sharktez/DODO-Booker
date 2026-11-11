-- ── InstaHelp Financial Configuration ────────────────────────────────────────
--
-- Creates per-mode financial config for InstaHelp (Scheduled and Instant are
-- completely independent — no cross-mode fallback).
--
-- Fields:
--   gst_percent                 — GST/tax rate applied to the taxable subtotal
--   platform_commission_percent — DODO platform cut (settlement use only)
--   surge_fee_*                 — optional surge fee on top of duration price
--   service_charge_*            — optional fixed/percentage service charge
--
-- Calculation order (applied to duration.finalPrice):
--   1. surge fee   → surgeAmount
--   2. service charge → serviceChargeAmount  (applied to base + surge)
--   3. GST         → gstAmount  (applied to base + surge + serviceCharge)
--   4. total       = base + surge + serviceCharge + gst
--
-- Also extends instahelp_bookings with a financial snapshot so every booking
-- records exactly what rates were applied at booking time.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Financial config table ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.instahelp_financial_config (
  id                           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  mode_id                      UUID          NOT NULL UNIQUE
                               REFERENCES public.instahelp_modes(id) ON DELETE CASCADE,

  -- GST / Tax
  gst_percent                  NUMERIC(6,4)  NOT NULL DEFAULT 0
                               CHECK (gst_percent >= 0 AND gst_percent <= 100),

  -- Platform commission (settlement calculation — not shown to customer)
  platform_commission_percent  NUMERIC(6,4)  NOT NULL DEFAULT 0
                               CHECK (platform_commission_percent >= 0 AND platform_commission_percent <= 100),

  -- Surge fee
  surge_fee_enabled            BOOLEAN       NOT NULL DEFAULT false,
  surge_fee_type               TEXT          NOT NULL DEFAULT 'percentage'
                               CHECK (surge_fee_type IN ('percentage', 'fixed')),
  surge_fee_value              NUMERIC(10,4) NOT NULL DEFAULT 0
                               CHECK (surge_fee_value >= 0),

  -- Additional service charge
  service_charge_enabled       BOOLEAN       NOT NULL DEFAULT false,
  service_charge_type          TEXT          NOT NULL DEFAULT 'fixed'
                               CHECK (service_charge_type IN ('percentage', 'fixed')),
  service_charge_value         NUMERIC(10,4) NOT NULL DEFAULT 0
                               CHECK (service_charge_value >= 0),

  updated_at                   TIMESTAMPTZ   NOT NULL DEFAULT now()
);

ALTER TABLE public.instahelp_financial_config ENABLE ROW LEVEL SECURITY;

-- Public read (anon + authenticated customers need this to calculate totals)
CREATE POLICY "instahelp_fc_public_read"
  ON public.instahelp_financial_config FOR SELECT
  USING (true);

-- Admin full access
CREATE POLICY "instahelp_fc_admin_all"
  ON public.instahelp_financial_config FOR ALL
  TO authenticated
  USING  (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

-- ── 2. Extend instahelp_bookings with financial snapshot ──────────────────────

ALTER TABLE public.instahelp_bookings
  ADD COLUMN IF NOT EXISTS gst_percent                 NUMERIC(6,4)  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gst_amount                  NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS platform_commission_percent NUMERIC(6,4)  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS platform_commission_amount  NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS surge_fee_enabled           BOOLEAN       NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS surge_fee_type              TEXT,
  ADD COLUMN IF NOT EXISTS surge_fee_value             NUMERIC(10,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS surge_fee_amount            NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS service_charge_enabled      BOOLEAN       NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS service_charge_type         TEXT,
  ADD COLUMN IF NOT EXISTS service_charge_value        NUMERIC(10,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS service_charge_amount       NUMERIC(12,2) NOT NULL DEFAULT 0;
