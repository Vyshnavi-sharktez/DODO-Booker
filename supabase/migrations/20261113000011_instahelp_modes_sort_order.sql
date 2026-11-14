-- Add sort_order to instahelp_modes for vendor-controlled tab ordering
ALTER TABLE instahelp_modes
  ADD COLUMN IF NOT EXISTS sort_order INT NOT NULL DEFAULT 0;

-- Set sensible defaults by mode_type
UPDATE instahelp_modes
SET sort_order = CASE mode_type
  WHEN 'scheduled' THEN 0
  WHEN 'instant'   THEN 1
  WHEN 'car_wash'  THEN 2
  ELSE 0
END;
