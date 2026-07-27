abstract final class RouteNames {
  static const String splash = 'splash';
  static const String login = 'login';
  static const String otp = 'otp';
  static const String dashboard = 'dashboard';
  static const String bookings = 'bookings';
  static const String bookingDetail = 'bookingDetail';
  static const String wallet = 'wallet';
  static const String services = 'services';
  static const String addService = 'addService';
  static const String notifications = 'notifications';
  static const String profile = 'profile';
  static const String documents = 'documents';
  static const String settings = 'settings';
  static const String subscription = 'subscription';
  static const String browsePlans = 'browsePlans';
  static const String planConfirmation = 'planConfirmation';
  static const String payment = 'payment';
}

abstract final class RoutePaths {
  static const String splash = '/';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String dashboard = '/dashboard';
  static const String bookings = '/bookings';
  static const String bookingDetail = '/bookings/:id';
  static const String wallet = '/wallet';
  static const String services = '/services';
  static const String addService = '/services/add';
  static const String notifications = '/notifications';
  static const String profile = '/profile';
  static const String documents = '/documents';
  static const String settings = '/settings';
  static const String subscription = '/subscription';
  static const String browsePlans = '/subscription/plans';
  static const String planConfirmation = '/subscription/confirm';
  static const String payment = '/subscription/payment';
}
