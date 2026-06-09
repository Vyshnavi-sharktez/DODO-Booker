-- Migration: Create settings table for key-value platform configuration
-- Run this in Supabase Dashboard → SQL Editor before launching the Settings module.

CREATE TABLE IF NOT EXISTS settings (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  setting_key   TEXT        NOT NULL UNIQUE,
  setting_value TEXT,
  created_at    TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at    TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_settings_key ON settings (setting_key);

-- Auto-update updated_at on row change
CREATE OR REPLACE FUNCTION fn_settings_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_settings_updated_at ON settings;
CREATE TRIGGER trg_settings_updated_at
  BEFORE UPDATE ON settings
  FOR EACH ROW EXECUTE FUNCTION fn_settings_updated_at();

-- Seed defaults (will not overwrite existing rows)
INSERT INTO settings (setting_key, setting_value) VALUES
  ('platform_name',                     'DODO Booker'),
  ('support_email',                     'support@dodobooker.com'),
  ('support_phone',                     ''),
  ('default_currency',                  'INR'),
  ('timezone',                          'Asia/Kolkata'),
  ('platform_commission_pct',           '10'),
  ('min_booking_amount',                '100'),
  ('max_booking_amount',                '50000'),
  ('auto_assign_vendor',                'false'),
  ('booking_cancellation_window_hours', '24'),
  ('booking_reschedule_limit',          '2'),
  ('advance_booking_days',              '30'),
  ('enable_email_notifications',        'true'),
  ('enable_push_notifications',         'true'),
  ('enable_sms_notifications',          'false'),
  ('vendor_approval_required',          'true'),
  ('vendor_commission_pct',             '80'),
  ('settlement_cycle_days',             '7'),
  ('allow_customer_registration',       'true'),
  ('allow_referral_program',            'false')
ON CONFLICT (setting_key) DO NOTHING;
