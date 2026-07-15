-- Adds nullable tax-breakdown snapshot columns to vendor_settlement_bookings.
--
-- Rows created BEFORE this migration have NULL in all three columns and are
-- treated as legacy records in the UI ("—" displayed, no recalculation).
-- Do NOT backfill or recalculate historical paid rows.
--
--   subtotal_before_tax  = booking.subtotal   (pre-tax service amount)
--   tax_amount           = booking.total_amount − booking.subtotal + booking.discount_amount
--   commission_base      = the amount Platform Commission was calculated on
--                          (= subtotal_before_tax for all new rows)

ALTER TABLE vendor_settlement_bookings
  ADD COLUMN IF NOT EXISTS subtotal_before_tax NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS tax_amount          NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS commission_base     NUMERIC(12,2);

COMMENT ON COLUMN vendor_settlement_bookings.subtotal_before_tax
  IS 'Pre-tax service amount (booking.subtotal). NULL for legacy rows.';
COMMENT ON COLUMN vendor_settlement_bookings.tax_amount
  IS 'Tax collected (total_amount - subtotal + discount). NULL for legacy rows.';
COMMENT ON COLUMN vendor_settlement_bookings.commission_base
  IS 'Amount Platform Commission was calculated on (= subtotal_before_tax). NULL for legacy rows.';
