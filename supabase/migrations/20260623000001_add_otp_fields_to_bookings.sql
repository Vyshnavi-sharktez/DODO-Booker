-- Adds fields required for OTP-based booking completion verification.
-- completion_otp: 6-digit code generated when vendor clicks "Complete Service".
-- otp_verified_at: timestamp set when customer OTP is successfully verified.

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS completion_otp   VARCHAR(6),
  ADD COLUMN IF NOT EXISTS otp_verified_at  TIMESTAMPTZ;
