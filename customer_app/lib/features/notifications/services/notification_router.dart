import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../routes/app_router.dart';
import '../../bookings/screens/booking_details_screen.dart';
import '../../bookings/services/bookings_providers.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../catalog/utils/catalog_launcher.dart';
import '../../vendor_custom_service/utils/custom_service_launcher.dart';
import '../../warranties/screens/warranty_details_screen.dart';
import '../../warranties/services/warranty_providers.dart';
import '../models/notification_model.dart';

/// Central notification router for the customer app.
/// Add one case here when a new feature needs notification routing — no widget
/// files need to change.
abstract final class CustomerNotificationRouter {
  static Future<void> handle(
    BuildContext context,
    WidgetRef ref,
    NotificationModel n,
  ) async {
    if (n.entityId == null) return;

    if (n.entityType == 'booking') {
      final isDesktop = MediaQuery.of(context).size.width >= 768;
      if (isDesktop) {
        // On desktop, show booking details as a floating modal directly over
        // the current page — no intermediate route needed.
        final targetContext = Navigator.of(context).context;
        Navigator.of(context).pop();
        final booking =
            await ref.read(bookingByIdProvider(n.entityId!).future);
        if (booking != null && targetContext.mounted) {
          PageSheet.show(
            targetContext,
            title: 'Booking Details',
            child: BookingDetailsScreen(booking: booking, inModal: true),
          );
        }
      } else {
        final route =
            AppRoutes.notificationBooking.replaceFirst(':id', n.entityId!);
        Navigator.of(context).pop();
        GoRouter.of(context).push(route);
      }
    } else if (n.entityType == 'custom_service_question') {
      // Vendor answered a question on a custom service → open service sheet.
      final customServiceId = n.entityId!;
      final targetContext = Navigator.of(context).context;
      Navigator.of(context).pop();
      if (targetContext.mounted) {
        await openCustomServiceQA(targetContext, customServiceId);
      }
    } else if (n.entityType == 'service_faq' ||
        n.entityType == 'customer_question' ||
        n.notificationType == 'question_answered') {
      // Admin answered a question on a catalog service → open catalog node.
      final serviceId = n.entityId!;
      final targetContext = Navigator.of(context).context;
      Navigator.of(context).pop();
      final node =
          await ref.read(catalogServiceProvider).fetchNode(serviceId);
      if (node != null && targetContext.mounted) {
        openCatalogNode(targetContext, node, parentId: n.parentNodeId);
      }
    } else if (n.entityType == 'service_warranty') {
      // Admin approved or rejected a warranty claim → open warranty details.
      final warrantyId = n.entityId!;
      final targetContext = Navigator.of(context).context;
      Navigator.of(context).pop();
      final warranty =
          await ref.read(warrantyByIdProvider(warrantyId).future);
      if (warranty != null && targetContext.mounted) {
        final booking =
            await ref.read(bookingByIdProvider(warranty.bookingId).future);
        if (booking != null && targetContext.mounted) {
          WarrantyDetailsScreen.showAsModal(
            targetContext,
            booking: booking,
            warranty: warranty,
          );
        }
      }
    }
  }
}
