-- Adds per-unit pricing to service_attributes for Number field types.
--
-- HOW IT IS USED
--   Admin sets price_per_unit on a Number attribute (e.g. sq.ft → ₹5/unit).
--   Customer enters a quantity (e.g. 100).
--   Price contribution = quantity × price_per_unit (e.g. ₹500).
--
-- WHAT IS NOT CHANGED
--   service_attribute_options.price_adjustment — flat per-option adjustment
--   used by dropdown / radio / checkbox attributes — is untouched.
--
-- SAFE TO RE-RUN: ADD COLUMN IF NOT EXISTS is idempotent.

ALTER TABLE service_attributes
  ADD COLUMN IF NOT EXISTS price_per_unit NUMERIC(10,2) DEFAULT NULL;
