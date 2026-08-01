-- AMC Quantity and Renewal Support
-- Adds quantity (number of units covered), previous_contract_id (renewal chain),
-- and is_renewal flag to amc_contracts.
-- Default 1 for quantity preserves backward compatibility for all existing rows.

ALTER TABLE public.amc_contracts
  ADD COLUMN IF NOT EXISTS quantity          INT     NOT NULL DEFAULT 1 CHECK (quantity > 0),
  ADD COLUMN IF NOT EXISTS previous_contract_id UUID  REFERENCES public.amc_contracts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_renewal        BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_amc_contracts_previous
  ON public.amc_contracts (previous_contract_id)
  WHERE previous_contract_id IS NOT NULL;

-- Extend status check to also allow 'pending' (for future use), keeping existing values.
-- No change to the constraint needed — existing statuses cover renewal workflow.
