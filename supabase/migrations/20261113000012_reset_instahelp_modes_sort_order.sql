-- Re-apply default sort_order for any modes that may have been scrambled
UPDATE instahelp_modes
SET sort_order = CASE mode_type
  WHEN 'scheduled' THEN 0
  WHEN 'instant'   THEN 1
  WHEN 'car_wash'  THEN 2
  ELSE 0
END;
