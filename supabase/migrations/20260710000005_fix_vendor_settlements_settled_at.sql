-- Fix vendor_settlements.settled_at: the column was created without a DEFAULT
-- so rows inserted before the Dart-side fix have NULL timestamps.
--
-- Use created_at as the best available proxy for when the settlement occurred;
-- fall back to CURRENT_TIMESTAMP if created_at is also NULL.

UPDATE vendor_settlements
SET settled_at = COALESCE(created_at, CURRENT_TIMESTAMP)
WHERE settled_at IS NULL;

-- Lock the column so this can never happen again.
ALTER TABLE vendor_settlements
  ALTER COLUMN settled_at SET DEFAULT now(),
  ALTER COLUMN settled_at SET NOT NULL;
