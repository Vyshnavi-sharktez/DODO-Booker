import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routes/route_names.dart';
import '../domain/models/vendor_notification.dart';

/// Central notification router for the vendor app.
/// Add one case here when a new feature needs notification routing — no widget
/// files need to change.
abstract final class VendorNotificationRouter {
  static void handle(
    BuildContext context,
    GoRouter router,
    VendorNotification n,
  ) {
    if ((n.entityType == 'booking' ||
            n.notificationType == 'vendor_assigned' ||
            n.notificationType == 'new_dispatch_offer' ||
            n.notificationType == 'vendor_reassigned') &&
        n.entityId != null) {
      Navigator.of(context).pop();
      router.pushNamed(
        RouteNames.bookingDetail,
        pathParameters: {'id': n.entityId!},
      );
    } else if (n.entityType == 'vendor_wallet' ||
        n.entityType == 'wallet' ||
        n.notificationType == 'wallet_low_balance' ||
        n.notificationType == 'wallet_alert' ||
        n.notificationType == 'wallet_penalty') {
      Navigator.of(context).pop();
      router.pushNamed(RouteNames.wallet);
    } else if (n.entityType == 'vendor_service_request' ||
        n.notificationType == 'vendor_service_request') {
      Navigator.of(context).pop();
      router.pushNamed(
        RouteNames.services,
        queryParameters: {'tab': '2'},
      );
    } else if (n.entityType == 'customer_question' ||
        n.notificationType == 'new_customer_question') {
      // Navigate to My Services → Questions sub-tab (tab=0, subTab=2).
      Navigator.of(context).pop();
      router.pushNamed(
        RouteNames.services,
        queryParameters: {'tab': '0', 'subTab': '2'},
      );
    }
  }
}
