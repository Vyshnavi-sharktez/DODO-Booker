-- Adds per-unit pricing support to service_attributes.
-- Used for Number field types (e.g. sq.ft, kg) where the price contribution
-- is: customer_entered_value × price_per_unit.
-- Option-based pricing (service_attribute_options.price_adjustment) is unchanged.

ALTER TABLE service_attributes
  ADD COLUMN IF NOT EXISTS price_per_unit NUMERIC(10,2) DEFAULT NULL;
