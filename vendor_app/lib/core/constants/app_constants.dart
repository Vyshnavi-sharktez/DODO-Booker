abstract final class AppConstants {
  // App metadata
  static const String appName = 'DODO Booker Vendor';
  static const String appVersion = '1.0.0';

  // Supabase table names
  static const String tableVendors = 'vendors';
  static const String tableBookings = 'bookings';
  static const String tableServices = 'services';
  static const String tableNotifications = 'notifications';
  static const String tableVendorSettlements = 'vendor_settlements';

  // SharedPreferences keys
  static const String keyAuthPhone = 'vendor_auth_phone';
  static const String keyOnboardingDone = 'vendor_onboarding_done';

  // Pagination
  static const int defaultPageSize = 20;

  // Booking statuses
  static const String statusPending = 'pending';
  static const String statusAssigned = 'assigned';
  static const String statusInProgress = 'in_progress';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';
}
