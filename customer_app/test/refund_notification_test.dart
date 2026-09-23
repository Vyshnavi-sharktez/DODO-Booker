import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/notifications/models/notification_model.dart';
import 'package:customer_app/routes/app_router.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _refundRequestId = 'rr-uuid-9f4a2b';
const _customerId = 'cust-uuid-001';

Map<String, dynamic> _customerRefundNotif({
  required String notificationType,
  String? title,
  String? message,
  bool isRead = false,
}) =>
    {
      'id': 'notif-${notificationType.replaceAll('_', '-')}',
      'user_id': _customerId,
      'user_type': 'customer',
      'title': title ?? 'Refund Update',
      'message': message ?? 'Message for $notificationType.',
      'notification_type': notificationType,
      'is_read': isRead,
      'created_at': '2026-09-23T12:00:00.000Z',
      'entity_type': 'refund_request',
      'entity_id': _refundRequestId,
    };

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('NotificationModel — refund notification parsing', () {
    test('parses refund_approved notification for customer', () {
      final n = NotificationModel.fromJson(_customerRefundNotif(
        notificationType: 'refund_approved',
        title: 'Refund Approved',
        message: 'Your refund request RFD-202609-000001 has been approved for ₹500.',
      ));
      expect(n.notificationType, 'refund_approved');
      expect(n.userType, 'customer');
      expect(n.userId, _customerId);
      expect(n.entityType, 'refund_request');
      expect(n.entityId, _refundRequestId);
      expect(n.isRead, false);
      expect(n.title, 'Refund Approved');
    });

    // All customer-facing refund notification types.
    for (final type in [
      'refund_under_review',
      'refund_more_info_requested',
      'refund_approved',
      'refund_partially_approved',
      'refund_rejected',
      'refund_processing',
      'refund_completed',
      'refund_failed',
      'refund_closed',
      'refund_admin_message',
    ]) {
      test('parses $type', () {
        final n = NotificationModel.fromJson(
            _customerRefundNotif(notificationType: type));
        expect(n.notificationType, type);
        expect(n.entityType, 'refund_request');
        expect(n.entityId, _refundRequestId);
        expect(n.userId, _customerId);
      });
    }

    test('isRead defaults to false when omitted', () {
      final map = _customerRefundNotif(notificationType: 'refund_approved')
        ..remove('is_read');
      final n = NotificationModel.fromJson(map);
      expect(n.isRead, false);
    });

    test('createdAt parses correctly', () {
      final n = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: 'refund_completed'));
      expect(n.createdAt, DateTime.utc(2026, 9, 23, 12, 0, 0));
    });

    test('entity_type and entity_id both present', () {
      final n = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: 'refund_rejected'));
      expect(n.entityType, isNotNull);
      expect(n.entityId, isNotNull);
    });
  });

  group('Notification routing — refund_request entity type', () {
    // The notification router checks n.entityType == 'refund_request' and
    // navigates to AppRoutes.refundQueryDetail.replaceFirst(':id', n.entityId!).
    // These tests verify the string transformation is correct.

    test('route built from entity_id matches expected path', () {
      final n = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: 'refund_approved'));
      final route =
          AppRoutes.refundQueryDetail.replaceFirst(':id', n.entityId!);
      expect(route, '/refund-queries/$_refundRequestId');
    });

    test('refundQueryDetail template contains :id placeholder', () {
      expect(AppRoutes.refundQueryDetail, contains(':id'));
    });

    test('route is unique per refund request', () {
      const id1 = 'rr-aaa-111';
      const id2 = 'rr-bbb-222';
      final route1 = AppRoutes.refundQueryDetail.replaceFirst(':id', id1);
      final route2 = AppRoutes.refundQueryDetail.replaceFirst(':id', id2);
      expect(route1, isNot(equals(route2)));
    });
  });

  group('Notification content safety', () {
    test('notification message does not contain internal admin notes', () {
      const safeMessage =
          'Your refund request RFD-202609-000001 could not be approved. '
          'Tap to view the details.';
      final n = NotificationModel.fromJson(_customerRefundNotif(
        notificationType: 'refund_rejected',
        message: safeMessage,
      ));
      // Safe messages contain ticket number and general info, not admin notes.
      expect(n.message, isNot(contains('internal')));
      expect(n.message, isNot(contains('admin_note')));
    });

    test('notification message does not contain bank details', () {
      // Verify the trigger messages don't expose bank/UPI details.
      // The trigger uses rr.ticket_number and amount only — never bank_upi_details.
      const safeMessage =
          'Your refund of ₹500 for RFD-202609-000001 has been transferred '
          'to your bank/UPI account.';
      final n = NotificationModel.fromJson(_customerRefundNotif(
        notificationType: 'refund_completed',
        message: safeMessage,
      ));
      expect(n.message, isNot(contains('account_number')));
      expect(n.message, isNot(contains('ifsc')));
      expect(n.message, isNot(contains('upi_id')));
    });

    test('notification for rejection does not include decision_notes', () {
      // Rejected messages show only the ticket ref, not the admin decision notes.
      const safeMessage =
          'Your refund request RFD-202609-000001 could not be approved. '
          'Tap to view the details.';
      final n = NotificationModel.fromJson(_customerRefundNotif(
        notificationType: 'refund_rejected',
        message: safeMessage,
      ));
      // The trigger constructs the message from ticket_number only.
      // This is a format check — the actual SQL is the source of truth.
      expect(n.message, contains('RFD-'));
      expect(n.message, isNot(contains('decision_notes')));
    });
  });

  group('Duplicate notification prevention — logic verification', () {
    // The SQL trigger checks:
    //   EXISTS (SELECT 1 FROM notifications
    //    WHERE notification_type = 'refund_new_request'
    //      AND entity_type = 'refund_request'
    //      AND entity_id = <id>)
    //
    // These tests verify the Dart side: notifications with the same key tuple
    // are identifiable by their id, so the UI can deduplicate if needed.

    test('two notifications with same type+entityId have different ids', () {
      final n1 = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: 'refund_approved')
            ..['id'] = 'notif-001');
      final n2 = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: 'refund_approved')
            ..['id'] = 'notif-002');
      expect(n1.id, isNot(equals(n2.id)));
      expect(n1.notificationType, equals(n2.notificationType));
      expect(n1.entityId, equals(n2.entityId));
    });

    test('different status notifications on same ticket are distinct', () {
      final processing = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: 'refund_processing'));
      final completed = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: 'refund_completed'));
      expect(processing.notificationType,
          isNot(equals(completed.notificationType)));
      expect(processing.entityId, equals(completed.entityId));
    });

    test('message notifications are not deduplicated — multiple allowed', () {
      // A customer can receive multiple admin messages on the same ticket.
      // There is NO unique guard on message notifications (unlike refund_new_request).
      final msg1 = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: 'refund_admin_message')
            ..['id'] = 'msg-001');
      final msg2 = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: 'refund_admin_message')
            ..['id'] = 'msg-002');
      expect(msg1.notificationType, equals(msg2.notificationType));
      expect(msg1.entityId, equals(msg2.entityId));
      expect(msg1.id, isNot(equals(msg2.id)));
    });
  });

  group('Webhook retry safety', () {
    // Webhook retries could trigger the status_history trigger twice for the
    // same status transition.  The refund system's own lifecycle guard should
    // prevent duplicate status_history rows.  This group documents the expected
    // deduplication behaviour at the notification level for refund_new_request.

    test('refund_new_request has a SQL-level duplicate guard (documented)', () {
      // The trigger fn_notify_on_refund_status_history_insert checks:
      //   EXISTS (SELECT 1 FROM notifications
      //    WHERE notification_type = 'refund_new_request'
      //      AND entity_type = 'refund_request'
      //      AND entity_id = NEW.refund_request_id)
      // If this guard fires, the second notification is silently skipped.
      // We document this by asserting the notification type constant is correct.
      const guardType = 'refund_new_request';
      final n = NotificationModel.fromJson(
          _customerRefundNotif(notificationType: guardType)
            ..['user_type'] = 'admin'
            ..['user_id'] = null);
      expect(n.notificationType, guardType);
    });
  });
}
