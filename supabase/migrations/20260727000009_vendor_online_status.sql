-- Add vendor-controlled online/offline availability flag.
--
-- is_online (vendor-controlled) is distinct from is_active (admin-controlled):
--   is_active = false → account deactivated by admin, vendor cannot log in or take jobs
--   is_online = false → vendor is temporarily unavailable (end-of-day, on leave, etc.)
--
-- Default is TRUE so all existing vendors are treated as online after migration.
-- A vendor is eligible for new booking assignment only when BOTH flags are true.

ALTER TABLE vendors
  ADD COLUMN IF NOT EXISTS is_online BOOLEAN NOT NULL DEFAULT true;

-- Expose vendor rows to Supabase Realtime so the admin panel receives UPDATE
-- events in real time when a vendor toggles their online status.
ALTER PUBLICATION supabase_realtime ADD TABLE vendors;
