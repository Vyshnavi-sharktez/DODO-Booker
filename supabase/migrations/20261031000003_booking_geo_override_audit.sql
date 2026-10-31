-- Audit columns for admin out-of-area vendor assignment overrides.
-- When an admin manually assigns a vendor who does not serve the booking
-- location, these fields record when the override occurred and which admin
-- approved it. NULL on both columns means no geo override was used.
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS geo_override_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS geo_override_admin_id UUID;
