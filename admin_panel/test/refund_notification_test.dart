import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/features/notifications/domain/models/app_notification.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _refundRequestId = 'rr-uuid-001';

Map<String, dynamic> _notifMap({
  required String notificationType,
  String userType = 'admin',
  String? userId,
  String entityType = 'refund_request',
  String entityId = _refundRequestId,
  bool isRead = false,
}) =>
    {
      'id': 'notif-${notificationType.replaceAll('_', '-')}',
      'user_type': userType,
      'user_id': userId,
      'title': 'Test Title',
      'message': 'Test message for $notificationType.',
      'notification_type': notificationType,
      'is_read': isRead,
      'created_at': '2026-09-23T10:00:00.000Z',
      'entity_type': entityType,
      'entity_id': entityId,
    };

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('AppNotification — refund notification types', () {
    test('parses refund_new_request (admin broadcast)', () {
      final n = AppNotification.fromMap(
          _notifMap(notificationType: 'refund_new_request', userId: null));
      expect(n.notificationType, 'refund_new_request');
      expect(n.userType, 'admin');
      expect(n.userId, ''); // fromMap coerces null to ''
      expect(n.entityType, 'refund_request');
      expect(n.entityId, _refundRequestId);
      expect(n.isRead, false);
    });

    test('parses refund_customer_message (admin broadcast)', () {
      final n = AppNotification.fromMap(
          _notifMap(notificationType: 'refund_customer_message', userId: null));
      expect(n.notificationType, 'refund_customer_message');
      expect(n.entityType, 'refund_request');
    });

    test('parses refund_bank_details_submitted (admin broadcast)', () {
      final n = AppNotification.fromMap(
          _notifMap(notificationType: 'refund_bank_details_submitted'));
      expect(n.notificationType, 'refund_bank_details_submitted');
      expect(n.entityType, 'refund_request');
    });

    test('parses refund_payment_failed (admin broadcast)', () {
      final n = AppNotification.fromMap(
          _notifMap(notificationType: 'refund_payment_failed'));
      expect(n.notificationType, 'refund_payment_failed');
      expect(n.entityType, 'refund_request');
    });

    test('isRead defaults to false when not set', () {
      final map = _notifMap(notificationType: 'refund_new_request')
        ..remove('is_read');
      final n = AppNotification.fromMap(map);
      expect(n.isRead, false);
    });

    test('copyWith toggles isRead', () {
      final n = AppNotification.fromMap(
          _notifMap(notificationType: 'refund_new_request'));
      final updated = n.copyWith(isRead: true);
      expect(updated.isRead, true);
      expect(updated.notificationType, n.notificationType);
      expect(updated.entityId, n.entityId);
    });

    test('createdAt parses correctly', () {
      final n = AppNotification.fromMap(
          _notifMap(notificationType: 'refund_new_request'));
      expect(n.createdAt, DateTime.utc(2026, 9, 23, 10, 0, 0));
    });
  });

  group('AppNotification — customer refund notifications', () {
    test('parses refund_approved targeted at customer', () {
      final n = AppNotification.fromMap(_notifMap(
        notificationType: 'refund_approved',
        userType: 'customer',
        userId: 'cust-uuid-001',
      ));
      expect(n.userType, 'customer');
      expect(n.userId, 'cust-uuid-001');
      expect(n.notificationType, 'refund_approved');
      expect(n.entityType, 'refund_request');
    });

    for (final status in [
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
      test('parses customer notification type: $status', () {
        final n = AppNotification.fromMap(_notifMap(
          notificationType: status,
          userType: 'customer',
          userId: 'cust-uuid-001',
        ));
        expect(n.notificationType, status);
        expect(n.entityType, 'refund_request');
        expect(n.entityId, _refundRequestId);
      });
    }
  });

  group('Duplicate prevention logic', () {
    // The SQL trigger uses:
    //   SELECT 1 FROM notifications
    //    WHERE notification_type = 'refund_new_request'
    //      AND entity_type = 'refund_request'
    //      AND entity_id = <refund_request_id>
    //
    // This group verifies that the key fields used in the guard are correctly
    // populated by fromMap, so a client-side re-check would also work.

    test('two notifications with same type+entity are distinguishable', () {
      final n1 = AppNotification.fromMap(_notifMap(
              notificationType: 'refund_new_request')
          ..[
              'id'
            ] = 'notif-001');
      final n2 = AppNotification.fromMap(_notifMap(
              notificationType: 'refund_new_request')
          ..[
              'id'
            ] = 'notif-002');
      // Same type and entity but different IDs — represents a duplicate that
      // the SQL guard should have blocked.  If it somehow reaches the client,
      // the id field lets us deduplicate.
      expect(n1.id, isNot(equals(n2.id)));
      expect(n1.notificationType, equals(n2.notificationType));
      expect(n1.entityId, equals(n2.entityId));
    });

    test('different statuses on same ticket are distinct notifications', () {
      final approved = AppNotification.fromMap(
          _notifMap(notificationType: 'refund_approved'));
      final completed = AppNotification.fromMap(
          _notifMap(notificationType: 'refund_completed'));
      expect(approved.notificationType, isNot(equals(completed.notificationType)));
      expect(approved.entityId, equals(completed.entityId));
    });
  });

  group('Routing key fields', () {
    test('entity_type refund_request and entity_id are populated', () {
      final n = AppNotification.fromMap(
          _notifMap(notificationType: 'refund_new_request'));
      // Admin panel _handleTap checks: n.entityType == 'refund_request'
      expect(n.entityType, 'refund_request');
      // entity_id is the refund_requests.id used to deep-link
      expect(n.entityId, isNotNull);
      expect(n.entityId, isNotEmpty);
    });

    test('null entity_id when not set — handled gracefully', () {
      final map = _notifMap(notificationType: 'refund_new_request')
        ..['entity_id'] = null;
      final n = AppNotification.fromMap(map);
      expect(n.entityId, isNull);
    });
  });
}
