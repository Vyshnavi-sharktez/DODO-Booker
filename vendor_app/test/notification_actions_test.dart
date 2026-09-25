import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/features/notifications/domain/models/vendor_notification.dart';

// Mirrors the display-state logic in _VendorNotificationsPanelDialogState
// and _NotificationsPageState.
bool resolveIsRead(
  VendorNotification n,
  Set<String> locallyRead,
  Set<String> locallyUnread,
) {
  if (locallyUnread.contains(n.id)) return false;
  return n.isRead || locallyRead.contains(n.id);
}

bool resolveIsDeleted(String id, Set<String> locallyDeleted) =>
    locallyDeleted.contains(id);

VendorNotification _notif({
  required String id,
  bool isRead = false,
  String type = 'system',
}) =>
    VendorNotification.fromMap({
      'id': id,
      'title': 'Test Notification',
      'message': 'Test message body.',
      'notification_type': type,
      'is_read': isRead,
      'created_at': '2026-09-25T10:00:00.000Z',
    });

void main() {
  group('VendorNotification action — isRead resolution', () {
    test('unread with no local override → not read', () {
      final n = _notif(id: 'n1', isRead: false);
      expect(resolveIsRead(n, {}, {}), isFalse);
    });

    test('unread + in locallyRead → read', () {
      final n = _notif(id: 'n1', isRead: false);
      expect(resolveIsRead(n, {'n1'}, {}), isTrue);
    });

    test('read with no local override → read', () {
      final n = _notif(id: 'n1', isRead: true);
      expect(resolveIsRead(n, {}, {}), isTrue);
    });

    test('read + in locallyUnread → not read', () {
      final n = _notif(id: 'n1', isRead: true);
      expect(resolveIsRead(n, {}, {'n1'}), isFalse);
    });

    test('locallyUnread takes precedence over locallyRead', () {
      final n = _notif(id: 'n1', isRead: false);
      expect(resolveIsRead(n, {'n1'}, {'n1'}), isFalse);
    });
  });

  group('VendorNotification action — toggle read state simulation', () {
    test('mark read then mark unread → not read', () {
      final n = _notif(id: 'n1', isRead: false);
      final locallyRead = <String>{};
      final locallyUnread = <String>{};

      locallyRead.add(n.id);
      locallyUnread.remove(n.id);
      expect(resolveIsRead(n, locallyRead, locallyUnread), isTrue);

      locallyUnread.add(n.id);
      locallyRead.remove(n.id);
      expect(resolveIsRead(n, locallyRead, locallyUnread), isFalse);
    });

    test('mark unread then mark read → read', () {
      final n = _notif(id: 'n1', isRead: true);
      final locallyRead = <String>{};
      final locallyUnread = <String>{};

      locallyUnread.add(n.id);
      locallyRead.remove(n.id);
      expect(resolveIsRead(n, locallyRead, locallyUnread), isFalse);

      locallyRead.add(n.id);
      locallyUnread.remove(n.id);
      expect(resolveIsRead(n, locallyRead, locallyUnread), isTrue);
    });
  });

  group('VendorNotification action — delete state', () {
    test('resolveIsDeleted returns true for deleted id', () {
      expect(resolveIsDeleted('n1', {'n1'}), isTrue);
    });

    test('resolveIsDeleted returns false for non-deleted id', () {
      expect(resolveIsDeleted('n2', {'n1'}), isFalse);
    });

    test('deleted notifications are excluded from visible list', () {
      final all = [_notif(id: 'n1'), _notif(id: 'n2'), _notif(id: 'n3')];
      final deleted = {'n2'};
      final visible = all.where((n) => !deleted.contains(n.id)).toList();
      expect(visible.length, 2);
      expect(visible.map((n) => n.id).toList(), ['n1', 'n3']);
    });

    test('deleting all notifications leaves empty visible list', () {
      final all = [_notif(id: 'n1'), _notif(id: 'n2')];
      final deleted = {'n1', 'n2'};
      final visible = all.where((n) => !deleted.contains(n.id)).toList();
      expect(visible, isEmpty);
    });
  });

  group('VendorNotification action — markAllRead excludes deleted', () {
    test('mark-all-read skips locally deleted items', () {
      final all = [
        _notif(id: 'n1', isRead: false),
        _notif(id: 'n2', isRead: false),
        _notif(id: 'n3', isRead: true),
      ];
      final deleted = {'n1'};
      final locallyRead = <String>{};
      final locallyUnread = <String>{};

      final toMarkRead = all
          .where((n) => !deleted.contains(n.id))
          .where((n) => !resolveIsRead(n, locallyRead, locallyUnread))
          .map((n) => n.id)
          .toSet();

      expect(toMarkRead, {'n2'});
    });
  });

  group('VendorNotification — copyWith isRead', () {
    test('copyWith preserves all fields except isRead', () {
      final original = _notif(id: 'n1', isRead: false);
      final updated = original.copyWith(isRead: true);
      expect(updated.isRead, isTrue);
      expect(updated.id, original.id);
      expect(updated.title, original.title);
      expect(updated.message, original.message);
    });
  });
}
