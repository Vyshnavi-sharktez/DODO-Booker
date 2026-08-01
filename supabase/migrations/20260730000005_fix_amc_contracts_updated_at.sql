-- amc_contracts.updated_at is missing from the actual table.
-- Two triggers reference this column:
--   1. trg_amc_contracts_updated_at (BEFORE UPDATE — sets new.updated_at = now())
--   2. fn_amc_visit_completed (AFTER UPDATE on bookings — updates amc_contracts.updated_at)
--
-- Root cause: 20260728000002_amc_schema.sql defined updated_at in the CREATE TABLE,
-- but if the table already existed (CREATE TABLE IF NOT EXISTS was a no-op), the
-- column was never added to the real table. Adding it here idempotently fixes both.

ALTER TABLE public.amc_contracts
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Recreate the BEFORE UPDATE trigger function and trigger so they are guaranteed
-- to exist and reference the now-present column.
CREATE OR REPLACE FUNCTION public.set_amc_contracts_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_amc_contracts_updated_at ON public.amc_contracts;

CREATE TRIGGER trg_amc_contracts_updated_at
  BEFORE UPDATE ON public.amc_contracts
  FOR EACH ROW EXECUTE FUNCTION public.set_amc_contracts_updated_at();
