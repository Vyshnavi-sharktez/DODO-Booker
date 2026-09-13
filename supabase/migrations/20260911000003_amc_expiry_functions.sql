-- ── AMC Expiry Functions ──────────────────────────────────────────────────────
--
-- 1. amc_contract_is_bookable(p_contract_id)
--    Single source of truth for booking eligibility.
--    Returns false when: not found, status ≠ 'active', or expires_at < now().
--    Used by the booking INSERT trigger (migration 20260911000004).
--
-- 2. expire_overdue_amc_contracts()
--    Lazy sweep: transitions active contracts whose expires_at has passed to
--    'expired'. Called by the customer app each time the AMC tab loads.
--    Targets ONLY status = 'active':
--      • 'paused' is excluded (D2 — pause freezes the expiry clock; expiry is
--        extended when admin approves resume).
--      • 'cancellation_requested' is excluded (D3 — admin must resolve the
--        cancellation first; expiry does not override it).
--      • Terminal statuses ('completed', 'cancelled', 'expired') are excluded.
--
-- 3. set_amc_contract_expires_at(p_contract_id, p_expires_at)
--    Admin-only: sets expires_at on contracts where it is still NULL (historical
--    custom-duration contracts whose duration was never snapshotted).
--    Safety guard: rejects if expires_at is already set, to prevent accidental
--    overwrites. Admin must contact support if an already-set value needs
--    correction.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. amc_contract_is_bookable ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.amc_contract_is_bookable(p_contract_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status     TEXT;
  v_expires_at TIMESTAMPTZ;
BEGIN
  SELECT status, expires_at
  INTO   v_status, v_expires_at
  FROM   public.amc_contracts
  WHERE  id = p_contract_id;

  -- Contract not found
  IF NOT FOUND THEN RETURN false; END IF;

  -- Only 'active' contracts are bookable; this also blocks paused, expired,
  -- completed, cancelled, and cancellation_requested in one check.
  IF v_status <> 'active' THEN RETURN false; END IF;

  -- Even if the status is still 'active', reject if the expiry has passed
  -- (handles the window before the lazy sweep has run).
  IF v_expires_at IS NOT NULL AND v_expires_at < now() THEN RETURN false; END IF;

  RETURN true;
END;
$$;

-- ── 2. expire_overdue_amc_contracts ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.expire_overdue_amc_contracts()
RETURNS SETOF uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.amc_contracts
  SET    status     = 'expired',
         updated_at = now()
  WHERE  status     = 'active'          -- D2: skip 'paused'; D3: skip 'cancellation_requested'
    AND  expires_at IS NOT NULL
    AND  expires_at < now()
  RETURNING id;
END;
$$;

-- ── 3. set_amc_contract_expires_at ────────────────────────────────────────────
-- Admin use only: provide a manual expiry date for historical custom contracts
-- whose package_duration_value was never snapshotted (expires_at = NULL).

CREATE OR REPLACE FUNCTION public.set_amc_contract_expires_at(
  p_contract_id uuid,
  p_expires_at  timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_expires_at IS NULL THEN
    RAISE EXCEPTION 'set_amc_contract_expires_at: p_expires_at must not be NULL'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.amc_contracts
  SET    expires_at = p_expires_at,
         updated_at = now()
  WHERE  id         = p_contract_id
    AND  expires_at IS NULL;   -- safety guard: never overwrite an existing value

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'set_amc_contract_expires_at: contract % not found or already has expires_at set',
      p_contract_id
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;
