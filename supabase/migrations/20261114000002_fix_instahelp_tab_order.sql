-- Force correct tab order for all existing vendors: Scheduled(0) → Instant(1) → Car Wash(2)
UPDATE instahelp_modes
SET sort_order = CASE mode_type
  WHEN 'scheduled' THEN 0
  WHEN 'instant'   THEN 1
  WHEN 'car_wash'  THEN 2
  ELSE sort_order
END;
