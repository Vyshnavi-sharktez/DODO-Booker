-- Drop legacy custom phone-OTP auth tables superseded by Supabase Auth phone OTP.
-- Both tables were created directly in the dashboard (no CREATE TABLE migration exists).
-- No application code reads or writes them; vendor_dev_auth had one dead write in the
-- admin vendor-creation wizard which has been removed alongside this migration.

DROP TABLE IF EXISTS public.vendor_dev_auth;
DROP TABLE IF EXISTS public.dev_auth;
