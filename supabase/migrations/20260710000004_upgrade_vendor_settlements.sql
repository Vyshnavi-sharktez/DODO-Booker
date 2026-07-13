-- Upgrade vendor_settlements to the columns expected by the current implementation.
--
-- Old schema had: booking_count, transaction_reference, status
-- Code expects:   vendor_name, completed_jobs_count, reference_number
--
-- Existing columns (id, vendor_id, amount, payment_method, notes, settled_by,
-- settled_at, created_at) are already present and are not touched.
-- Obsolete columns (booking_count, transaction_reference, status) are left in
-- place so no existing data is lost.

ALTER TABLE vendor_settlements
  ADD COLUMN IF NOT EXISTS vendor_name          TEXT    NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS completed_jobs_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reference_number     TEXT;
