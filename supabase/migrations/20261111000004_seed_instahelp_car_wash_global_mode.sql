-- Seed the global (admin-managed, vendor_id IS NULL) Car Wash mode and its
-- default slot config so the admin InstaHelp page can configure it and the
-- check_instahelp_instant_availability RPC can apply its hours.

INSERT INTO public.instahelp_modes (mode_type, is_active, vendor_id)
VALUES ('car_wash', TRUE, NULL)
ON CONFLICT DO NOTHING;

-- Seed default slot config for the new global car_wash row (08:00–20:00, all days).
INSERT INTO public.instahelp_slot_config
  (mode_id, working_days, start_time, end_time, slot_interval_minutes, max_bookings_per_slot)
SELECT id, '[0,1,2,3,4,5,6]'::jsonb, '08:00', '20:00', 60, 10
FROM   public.instahelp_modes
WHERE  mode_type = 'car_wash' AND vendor_id IS NULL
ON CONFLICT (mode_id) DO NOTHING;
