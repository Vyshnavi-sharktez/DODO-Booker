import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/features/broadcast_notifications/domain/models/broadcast_notification.dart';

void main() {
  group('BroadcastNotification.fromMap', () {
    test('parses a fully-populated row', () {
      final map = {
        'id': 'abc-123',
        'title': 'Summer Sale!',
        'message': 'Get 20% off all services this weekend.',
        'notification_type': 'offer',
        'audience': 'customers',
        'image_url': 'https://example.com/img.png',
        'deep_link': 'dodo://services',
        'targeting_type': 'serving_area',
        'targeting_value': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'targeting_label': 'KPHB Colony',
        'status': 'sent',
        'scheduled_at': null,
        'sent_at': '2026-10-08T10:00:00.000Z',
        'recipient_count': 42,
        'created_at': '2026-10-08T09:00:00.000Z',
        'updated_at': '2026-10-08T10:00:00.000Z',
      };

      final n = BroadcastNotification.fromMap(map);

      expect(n.id, 'abc-123');
      expect(n.title, 'Summer Sale!');
      expect(n.message, 'Get 20% off all services this weekend.');
      expect(n.notificationType, 'offer');
      expect(n.audience, 'customers');
      expect(n.imageUrl, 'https://example.com/img.png');
      expect(n.deepLink, 'dodo://services');
      expect(n.targetingType, 'serving_area');
      expect(n.targetingValue, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect(n.targetingLabel, 'KPHB Colony');
      expect(n.status, 'sent');
      expect(n.scheduledAt, isNull);
      expect(n.sentAt, isNotNull);
      expect(n.recipientCount, 42);
      expect(n.createdAt, isNotNull);
    });

    test('uses defaults for missing optional fields', () {
      final map = {
        'id': 'xyz-999',
        'title': 'Hi',
        'message': 'Hello world',
        'notification_type': 'announcement',
        'audience': 'vendors',
        'targeting_type': 'all',
        'status': 'draft',
        'recipient_count': 0,
      };

      final n = BroadcastNotification.fromMap(map);

      expect(n.imageUrl, isNull);
      expect(n.deepLink, isNull);
      expect(n.targetingValue, isNull);
      expect(n.targetingLabel, isNull);
      expect(n.scheduledAt, isNull);
      expect(n.sentAt, isNull);
      expect(n.recipientCount, 0);
    });

    test('parses scheduled broadcast with scheduledAt', () {
      final map = {
        'id': 'sched-1',
        'title': 'Reminder',
        'message': 'Book your service today!',
        'notification_type': 'custom',
        'audience': 'both',
        'targeting_type': 'all',
        'status': 'scheduled',
        'scheduled_at': '2026-10-09T15:30:00.000Z',
        'recipient_count': 0,
      };

      final n = BroadcastNotification.fromMap(map);

      expect(n.status, 'scheduled');
      expect(n.scheduledAt, isNotNull);
      expect(n.scheduledAt!.isUtc, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      final original = BroadcastNotification.fromMap({
        'id': 'copy-1',
        'title': 'Original',
        'message': 'Original message',
        'notification_type': 'announcement',
        'audience': 'customers',
        'targeting_type': 'all',
        'status': 'draft',
        'recipient_count': 0,
      });

      final updated = original.copyWith(status: 'sent', recipientCount: 5);

      expect(updated.id, 'copy-1');
      expect(updated.title, 'Original');
      expect(updated.status, 'sent');
      expect(updated.recipientCount, 5);
    });
  });

  group('BroadcastNotification status checks', () {
    test('draft is not sent or scheduled', () {
      final b = BroadcastNotification.fromMap({
        'id': 'draft-1',
        'title': 'Draft',
        'message': 'msg',
        'notification_type': 'announcement',
        'audience': 'customers',
        'targeting_type': 'all',
        'status': 'draft',
        'recipient_count': 0,
      });
      expect(b.status, 'draft');
      expect(b.sentAt, isNull);
      expect(b.scheduledAt, isNull);
    });

    test('recognises all valid notification types', () {
      const types = ['offer', 'new_service', 'announcement', 'custom'];
      for (final t in types) {
        final b = BroadcastNotification.fromMap({
          'id': 'type-$t',
          'title': 'T',
          'message': 'M',
          'notification_type': t,
          'audience': 'customers',
          'targeting_type': 'all',
          'status': 'draft',
          'recipient_count': 0,
        });
        expect(b.notificationType, t);
      }
    });

    test('recognises all valid audience values', () {
      const audiences = ['customers', 'vendors', 'both'];
      for (final a in audiences) {
        final b = BroadcastNotification.fromMap({
          'id': 'aud-$a',
          'title': 'T',
          'message': 'M',
          'notification_type': 'announcement',
          'audience': a,
          'targeting_type': 'all',
          'status': 'draft',
          'recipient_count': 0,
        });
        expect(b.audience, a);
      }
    });
  });
}
