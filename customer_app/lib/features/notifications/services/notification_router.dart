import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../routes/app_router.dart';
import '../../support/screens/support_chat_screen.dart';
import '../../bookings/screens/booking_details_screen.dart';
import '../../bookings/services/bookings_providers.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../catalog/utils/catalog_launcher.dart';
import '../../refund_queries/screens/refund_queries_flow.dart';
import '../../vendor_custom_service/utils/custom_service_launcher.dart';
import '../../warranties/screens/warranty_details_screen.dart';
import '../../warranties/services/warranty_providers.dart';
import '../models/notification_model.dart';

/// Central notification router for the customer app.
/// Add one case here when a new feature needs notification routing — no widget
/// files need to change.
abstract final class CustomerNotificationRouter {
  /// Called from in-app notification tiles.
  /// Pops the notification panel first, then navigates.
  static Future<void> handle(
    BuildContext context,
    WidgetRef ref,
    NotificationModel n,
  ) async {
    if (n.entityId == null) return;
    Navigator.of(context).pop();
    await _routeByEntity(context, ref, n);
  }

  /// Called from FCM tap events (cold start / background / foreground local tap).
  /// Does NOT call Navigator.pop() — there is no overlay to dismiss.
  static Future<void> handleFromPush(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> data,
  ) async {
    final n = _modelFromFcmData(data);
    if (n.entityId == null) return;
    await _routeByEntity(context, ref, n);
  }

  static NotificationModel _modelFromFcmData(Map<String, dynamic> data) {
    String? nonEmpty(String? v) =>
        (v != null && v.isNotEmpty) ? v : null;
    return NotificationModel(
      id: data['notification_id'] as String? ?? '',
      userId: null,
      userType: 'customer',
      title: '',
      message: '',
      notificationType: data['notification_type'] as String?,
      isRead: false,
      createdAt: DateTime.now(),
      entityType: nonEmpty(data['entity_type'] as String?),
      entityId: nonEmpty(data['entity_id'] as String?),
      parentNodeId: nonEmpty(data['parent_node_id'] as String?),
      customerQuestionId: nonEmpty(data['customer_question_id'] as String?),
    );
  }

  static Future<void> _routeByEntity(
    BuildContext context,
    WidgetRef ref,
    NotificationModel n,
  ) async {
    if (n.entityType == 'booking') {
      final isDesktop = MediaQuery.of(context).size.width >= 768;
      if (isDesktop) {
        final booking =
            await ref.read(bookingByIdProvider(n.entityId!).future);
        if (booking != null && context.mounted) {
          PageSheet.show(
            context,
            title: 'Booking Details',
            child: BookingDetailsScreen(booking: booking, inModal: true),
          );
        }
      } else {
        final route =
            AppRoutes.notificationBooking.replaceFirst(':id', n.entityId!);
        if (context.mounted) appRouter.push(route);
      }
    } else if (n.entityType == 'custom_service_question') {
      final customServiceId = n.entityId!;
      if (context.mounted) {
        await openCustomServiceQA(context, customServiceId);
      }
    } else if (n.entityType == 'service_faq' ||
        n.entityType == 'customer_question' ||
        n.notificationType == 'question_answered') {
      final serviceId = n.entityId!;
      final node =
          await ref.read(catalogServiceProvider).fetchNode(serviceId);
      if (node != null && context.mounted) {
        openCatalogNode(context, node, parentId: n.parentNodeId);
      }
    } else if (n.entityType == 'service_warranty') {
      final warrantyId = n.entityId!;
      final warranty =
          await ref.read(warrantyByIdProvider(warrantyId).future);
      if (warranty != null && context.mounted) {
        final booking =
            await ref.read(bookingByIdProvider(warranty.bookingId).future);
        if (booking != null && context.mounted) {
          WarrantyDetailsScreen.showAsModal(
            context,
            booking: booking,
            warranty: warranty,
          );
        }
      }
    } else if (n.entityType == 'refund_request') {
      if (context.mounted) {
        PageSheet.show(
          context,
          title: 'Refund Queries',
          child: RefundQueriesFlow(initialRequestId: n.entityId!),
        );
      }
    } else if (n.entityType == 'support_conversation') {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupportChatScreen()),
        );
      }
    }
  }
}
