// Default values for all settings keys.
//
// Scalability: adding a new setting requires only:
//   1. One new entry here (the default value)
//   2. One new SettingFieldDef entry in the relevant section in settings_page.dart
//
// No changes to the repository, notifier, or database schema are needed —
// the settings table is generic key-value storage.
const Map<String, String> kSettingDefaults = {
  // General
  'platform_name': 'DODO Booker',
  'support_email': 'support@dodobooker.com',
  'support_phone': '',
  'default_currency': 'INR',
  'timezone': 'Asia/Kolkata',

  // Business
  'platform_commission_pct': '10',
  'min_booking_amount': '100',
  'max_booking_amount': '50000',
  'auto_assign_vendor': 'false',

  // Booking
  'booking_cancellation_window_hours': '24',
  'booking_reschedule_limit': '2',
  'advance_booking_days': '30',

  // Notification
  'enable_email_notifications': 'true',
  'enable_push_notifications': 'true',
  'enable_sms_notifications': 'false',

  // Vendor
  'vendor_approval_required': 'true',
  'vendor_commission_pct': '80',
  'settlement_cycle_days': '7',

  // Customer
  'allow_customer_registration': 'true',
  'allow_referral_program': 'false',
};
