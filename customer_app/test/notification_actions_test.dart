import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/notifications/models/notification_model.dart';

// Mirrors the display-state logic in _NotificationsModalState.
bool resolveIsRead(
  NotificationModel n,
  Set<String> locallyRead,
  Set<String> locallyUnread,
) {
  if (locallyUnread.contains(n.id)) return false;
  return n.isRead || locallyRead.contains(n.id);
}

bool resolveIsDeleted(String id, Set<String> locallyDeleted) =>
    locallyDeleted.contains(id);

Map<String, dynamic> _notif({
  required String id,
  bool isRead = false,
  String type = 'system',
}) =>
    {
      'id': id,
      'user_id': 'cust-001',
      'user_type': 'customer',
      'title': 'Test Notification',
      'message': 'Test message body.',
      'notification_type': type,
      'is_read': isRead,
      'created_at': '2026-09-25T10:00:00.000Z',
    };

void main() {
  group('Notification action — isRead resolution', () {
    test('unread with no local override → not read', () {
      final n = NotificationModel.fromJson(_notif(id: 'n1', isRead: false));
      expect(resolveIsRead(n, {}, {}), isFalse);
    });

    test('unread + in locallyRead → read', () {
      final n = NotificationModel.fromJson(_notif(id: 'n1', isRead: false));
      expect(resolveIsRead(n, {'n1'}, {}), isTrue);
    });

    test('read with no local override → read', () {
      final n = NotificationModel.fromJson(_notif(id: 'n1', isRead: true));
      expect(resolveIsRead(n, {}, {}), isTrue);
    });

    test('read + in locallyUnread → not read', () {
      final n = NotificationModel.fromJson(_notif(id: 'n1', isRead: true));
      expect(resolveIsRead(n, {}, {'n1'}), isFalse);
    });

    test('locallyUnread takes precedence over locallyRead', () {
      final n = NotificationModel.fromJson(_notif(id: 'n1', isRead: false));
      expect(resolveIsRead(n, {'n1'}, {'n1'}), isFalse);
    });

    test('different id in locallyRead does not affect this notification', () {
      final n = NotificationModel.fromJson(_notif(id: 'n1', isRead: false));
      expect(resolveIsRead(n, {'n2'}, {}), isFalse);
    });
  });

  group('Notification action — toggle read state simulation', () {
    test('mark read then mark unread → not read', () {
      final n = NotificationModel.fromJson(_notif(id: 'n1', isRead: false));
      final locallyRead = <String>{};
      final locallyUnread = <String>{};

      // Mark read
      locallyRead.add(n.id);
      locallyUnread.remove(n.id);
      expect(resolveIsRead(n, locallyRead, locallyUnread), isTrue);

      // Mark unread
      locallyUnread.add(n.id);
      locallyRead.remove(n.id);
      expect(resolveIsRead(n, locallyRead, locallyUnread), isFalse);
    });

    test('mark unread then mark read → read', () {
      final n = NotificationModel.fromJson(_notif(id: 'n1', isRead: true));
      final locallyRead = <String>{};
      final locallyUnread = <String>{};

      // Mark unread
      locallyUnread.add(n.id);
      locallyRead.remove(n.id);
      expect(resolveIsRead(n, locallyRead, locallyUnread), isFalse);

      // Mark read
      locallyRead.add(n.id);
      locallyUnread.remove(n.id);
      expect(resolveIsRead(n, locallyRead, locallyUnread), isTrue);
    });
  });

  group('Notification action — delete state', () {
    test('resolveIsDeleted returns true for deleted id', () {
      expect(resolveIsDeleted('n1', {'n1'}), isTrue);
    });

    test('resolveIsDeleted returns false for non-deleted id', () {
      expect(resolveIsDeleted('n2', {'n1'}), isFalse);
    });

    test('resolveIsDeleted returns false with empty set', () {
      expect(resolveIsDeleted('n1', {}), isFalse);
    });

    test('deleted notifications are excluded from visible list', () {
      final all = [
        NotificationModel.fromJson(_notif(id: 'n1')),
        NotificationModel.fromJson(_notif(id: 'n2')),
        NotificationModel.fromJson(_notif(id: 'n3')),
      ];
      final deleted = {'n2'};
      final visible = all.where((n) => !deleted.contains(n.id)).toList();
      expect(visible.length, 2);
      expect(visible.map((n) => n.id).toList(), ['n1', 'n3']);
    });

    test('deleting all notifications leaves empty visible list', () {
      final all = [
        NotificationModel.fromJson(_notif(id: 'n1')),
        NotificationModel.fromJson(_notif(id: 'n2')),
      ];
      final deleted = {'n1', 'n2'};
      final visible = all.where((n) => !deleted.contains(n.id)).toList();
      expect(visible, isEmpty);
    });
  });

  group('Notification action — unread count after delete', () {
    test('deleting an unread item reduces effective unread count', () {
      final all = [
        NotificationModel.fromJson(_notif(id: 'n1', isRead: false)),
        NotificationModel.fromJson(_notif(id: 'n2', isRead: false)),
        NotificationModel.fromJson(_notif(id: 'n3', isRead: true)),
      ];
      final deleted = {'n1'};
      final locallyRead = <String>{};
      final locallyUnread = <String>{};

      final unreadCount = all
          .where((n) => !deleted.contains(n.id))
          .where((n) => !resolveIsRead(n, locallyRead, locallyUnread))
          .length;
      expect(unreadCount, 1);
    });
  });
}
