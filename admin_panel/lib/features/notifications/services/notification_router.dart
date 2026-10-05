import 'package:go_router/go_router.dart';

/// Routes FCM push taps to the correct admin dashboard page.
/// Called from DodoAdminApp — no overlay to pop, no WidgetRef needed for dialogs.
abstract final class AdminNotificationRouter {
  static void handleFromPush(GoRouter router, Map<String, dynamic> data) {
    final entityType = data['entity_type'] as String?;
    final entityId =
        (data['entity_id'] as String?)?.isNotEmpty == true ? data['entity_id'] as String : null;
    final notificationType = data['notification_type'] as String?;

    if (entityType == 'vendor_service_request' ||
        entityType == 'custom_service_question') {
      router.go('/dashboard/vendor-service-requests');
    } else if (entityType == 'booking' ||
        notificationType == 'vendor_accepted') {
      router.go('/dashboard/bookings');
    } else if (entityType == 'amc_scheduling_request' ||
        entityType == 'amc_resume_request') {
      router.go('/dashboard/amc-scheduling-requests');
    } else if (entityType == 'customer_question') {
      router.go('/dashboard/catalog');
    } else if (entityType == 'service_warranty') {
      router.go('/dashboard/warranty-claims');
    } else if (entityType == 'amc_contract') {
      router.go('/dashboard/bookings');
    } else if (entityType == 'vendor_document' && entityId != null) {
      router.go('/dashboard/vendors/$entityId?tab=1');
    } else if (notificationType == 'subscription_purchased') {
      router.go('/dashboard/vendor-subscriptions');
    } else if (entityType == 'refund_request') {
      router.go('/dashboard/refunds');
    } else if (entityType == 'support_conversation') {
      router.go('/dashboard/support');
    } else {
      router.go('/dashboard');
    }
  }
}
