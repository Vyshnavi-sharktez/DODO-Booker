-- ── AMC Expiry INSERT Trigger ─────────────────────────────────────────────────
--
-- Fires BEFORE INSERT on amc_contracts.
--
-- Responsibilities:
--   1. Validates that custom-duration contracts supply a positive
--      package_duration_value (D5 — no silent perpetual contracts).
--   2. Computes and sets expires_at from the contract's own fields so
--      expires_at is always in sync with created_at at purchase time.
--
-- The trigger fires on INSERT ONLY, never on UPDATE.  This means:
--   • expires_at is immutable after creation for normal operations.
--   • The admin resume-approval flow (D2) can extend expires_at via an
--     explicit UPDATE without this trigger interfering.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_set_amc_expires_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- D5: custom duration MUST have a valid positive value.
  -- Reject the INSERT rather than silently treating NULL as perpetual.
  IF NEW.package_duration = 'custom' THEN
    IF NEW.package_duration_value IS NULL OR NEW.package_duration_value <= 0 THEN
      RAISE EXCEPTION
        'amc_custom_duration_required: package_duration=''custom'' requires a positive package_duration_value'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Compute expires_at from the contract's own snapshotted fields.
  -- NEW.created_at defaults to now() so this is always the purchase timestamp.
  NEW.expires_at := CASE NEW.package_duration
    WHEN 'monthly'     THEN NEW.created_at + INTERVAL '30 days'
    WHEN 'quarterly'   THEN NEW.created_at + INTERVAL '91 days'
    WHEN 'half_yearly' THEN NEW.created_at + INTERVAL '182 days'
    WHEN 'yearly'      THEN NEW.created_at + INTERVAL '365 days'
    ELSE
      -- 'custom' with validated positive value
      NEW.created_at + (NEW.package_duration_value || ' days')::INTERVAL
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_amc_expires_at ON public.amc_contracts;

CREATE TRIGGER trg_set_amc_expires_at
  BEFORE INSERT ON public.amc_contracts
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_set_amc_expires_at();
