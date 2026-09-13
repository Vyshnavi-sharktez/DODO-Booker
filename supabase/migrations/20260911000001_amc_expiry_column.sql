-- ── AMC Expiry Column ─────────────────────────────────────────────────────────
--
-- 1. Adds 'expired' to the status CHECK constraint.
-- 2. Adds expires_at TIMESTAMPTZ (nullable) — the authoritative expiry timestamp.
-- 3. Adds package_duration_value and service_interval_value to amc_contracts.
--    These columns have never existed on this table; they live on amc_plans only.
--    They are added here so:
--      a) The BEFORE INSERT trigger (migration 20260911000002) can validate and
--         compute expires_at for new 'custom'-duration contracts.
--      b) checkout_service.dart can snapshot them at purchase time.
-- 4. Backfills expires_at for ALL existing contracts (D1) using only
--    package_duration — the named durations ('monthly', 'quarterly', etc.)
--    map directly to fixed day counts. 'custom' and NULL remain at expires_at =
--    NULL because package_duration_value was never written to amc_contracts before
--    this release (admin must set these manually via set_amc_contract_expires_at).
-- 5. No existing contract statuses are changed (D4 — lazy expiry only).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Extend status CHECK to include 'expired' ───────────────────────────────

ALTER TABLE public.amc_contracts
  DROP CONSTRAINT IF EXISTS amc_contracts_status_check;

ALTER TABLE public.amc_contracts
  ADD CONSTRAINT amc_contracts_status_check
  CHECK (status IN (
    'active',
    'paused',
    'completed',
    'cancelled',
    'cancellation_requested',
    'expired'
  ));

-- ── 2. Add expires_at column (nullable) ───────────────────────────────────────

ALTER TABLE public.amc_contracts
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- ── 3. Add duration/interval value columns (never existed on this table) ──────
--
-- package_duration_value: number of days for package_duration = 'custom'.
--   Required by the BEFORE INSERT trigger to compute expires_at.
--   Snapshotted at checkout so existing contract rows remain self-contained.
--
-- service_interval_value: number of days for service_interval = 'custom'.
--   Snapshotted for completeness; not used by the expiry trigger.

ALTER TABLE public.amc_contracts
  ADD COLUMN IF NOT EXISTS package_duration_value INTEGER,
  ADD COLUMN IF NOT EXISTS service_interval_value INTEGER;

-- ── 4. Backfill expires_at for all existing contracts ─────────────────────────
--
-- Uses only package_duration (already on the table since 20260729_amc_plans.sql).
-- Named durations map to fixed day counts; everything else (including 'custom'
-- and NULL) remains NULL — those contracts never had a value to derive from.
-- Idempotent: WHERE expires_at IS NULL means re-running is safe.

UPDATE public.amc_contracts
SET expires_at = CASE package_duration
  WHEN 'monthly'     THEN created_at + INTERVAL '30 days'
  WHEN 'quarterly'   THEN created_at + INTERVAL '91 days'
  WHEN 'half_yearly' THEN created_at + INTERVAL '182 days'
  WHEN 'yearly'      THEN created_at + INTERVAL '365 days'
  ELSE NULL
END
WHERE expires_at IS NULL;

-- ── 5. Index for the lazy expiry sweep ───────────────────────────────────────
-- Only active contracts with a set expiry date are candidates for the sweep.

CREATE INDEX IF NOT EXISTS idx_amc_contracts_active_expiry
  ON public.amc_contracts (expires_at)
  WHERE status = 'active' AND expires_at IS NOT NULL;
