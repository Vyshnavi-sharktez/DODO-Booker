-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 3: Minimum Wallet Balance Enforcement
--
-- Blocks vendor assignment on a booking when the vendor's
-- vendor_wallets.available_balance is below the global minimum.
--
-- Configuration:
--   settings.wallet_minimum_balance (TEXT, numeric value, default '0')
--   '0' or absent → enforcement disabled (existing behaviour preserved).
--
-- Scope:
--   - Blocks any assignment where NEW.vendor_id is non-null, including
--     re-confirmation of the same vendor (e.g. just updating service_date on
--     an already-assigned booking). This ensures the check is never bypassed
--     by a same-vendor re-submit.
--   - Eligibility is re-evaluated on each assignment, so a vendor whose
--     balance is topped up above the minimum immediately becomes eligible again.
--
-- Payout module: not referenced, not modified.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Global config seed ────────────────────────────────────────────────────────
-- Default '0' disables enforcement until an admin sets a real minimum.

INSERT INTO settings (setting_key, setting_value)
VALUES ('wallet_minimum_balance', '0')
ON CONFLICT (setting_key) DO NOTHING;

-- ── Trigger function ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_enforce_wallet_minimum_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_minimum         NUMERIC;
  v_available       NUMERIC;
  v_minimum_setting TEXT;
BEGIN
  -- Skip only when the vendor slot is being cleared (unassign).
  -- Same-vendor re-submissions still run the check so a vendor whose balance
  -- dropped below the minimum after initial assignment cannot receive new work
  -- by the admin simply re-confirming without changing the vendor.
  IF NEW.vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Read global minimum from settings; treat missing/non-numeric as 0.
  SELECT setting_value INTO v_minimum_setting
    FROM settings
   WHERE setting_key = 'wallet_minimum_balance';

  v_minimum := COALESCE(NULLIF(TRIM(v_minimum_setting), '')::NUMERIC, 0);

  -- Enforcement disabled when minimum is zero.
  IF v_minimum <= 0 THEN
    RETURN NEW;
  END IF;

  -- Read vendor's available balance.
  SELECT available_balance INTO v_available
    FROM vendor_wallets
   WHERE vendor_id = NEW.vendor_id;

  -- No wallet row → treat as zero balance.
  IF NOT FOUND THEN
    v_available := 0;
  END IF;

  -- Block assignment if balance is below the minimum.
  IF v_available < v_minimum THEN
    RAISE EXCEPTION
      'Vendor wallet balance (%) is below the required minimum (%). '
      'Top up the wallet before assigning new bookings.',
      v_available, v_minimum
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- ── Trigger ───────────────────────────────────────────────────────────────────
-- BEFORE so the exception aborts the write before it reaches the table.
-- OF vendor_id limits invocation to rows where vendor_id appears in the SET
-- clause (PostgREST always includes it for assignment payloads).

DROP TRIGGER IF EXISTS trg_enforce_wallet_minimum_balance ON bookings;

CREATE TRIGGER trg_enforce_wallet_minimum_balance
  BEFORE INSERT OR UPDATE OF vendor_id ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_enforce_wallet_minimum_balance();
