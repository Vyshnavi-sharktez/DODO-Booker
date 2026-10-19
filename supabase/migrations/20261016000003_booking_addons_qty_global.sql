-- Add quantity and is_global columns to booking_addons.
-- quantity: how many of this add-on are included (defaults to 1 for all existing rows).
-- is_global: true when the add-on comes from the global pool rather than a per-service assignment.

ALTER TABLE booking_addons
  ADD COLUMN IF NOT EXISTS quantity  INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS is_global BOOLEAN NOT NULL DEFAULT FALSE;
