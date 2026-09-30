-- Clear completion_otp from all completed bookings.
-- The OTP served its purpose (service verification) and should not be shown
-- after the booking is completed.

UPDATE public.bookings
SET completion_otp = NULL
WHERE status = 'completed'
  AND completion_otp IS NOT NULL;
