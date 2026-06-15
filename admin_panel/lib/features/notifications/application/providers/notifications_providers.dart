import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/notifications_repository.dart';
import '../../domain/models/app_notification.dart';

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.watch(supabaseClientProvider));
});

class NotificationsNotifier
    extends StateNotifier<AsyncValue<List<AppNotification>>> {
  final NotificationsRepository _repo;

  NotificationsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchNotifications);
  }

  Future<void> refresh() => _load();

  Future<void> createNotification({
    required String userType,
    required String userId,
    required String title,
    required String message,
    required String notificationType,
    String? entityType,
    String? entityId,
  }) async {
    final created = await _repo.createNotification(
      userType: userType,
      userId: userId,
      title: title,
      message: message,
      notificationType: notificationType,
      entityType: entityType,
      entityId: entityId,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([created, ...current]);
  }

  Future<void> toggleRead(String id, {required bool currentIsRead}) async {
    final newIsRead = !currentIsRead;
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((n) => n.id == id ? n.copyWith(isRead: newIsRead) : n)
            .toList(),
      );
    }
    try {
      await _repo.updateReadStatus(id, isRead: newIsRead);
    } catch (e) {
      await _load();
      rethrow;
    }
  }

  Future<void> bulkMarkAsRead(List<String> ids) async {
    final current = state.valueOrNull;
    if (current != null) {
      final idSet = ids.toSet();
      state = AsyncValue.data(
        current
            .map((n) => idSet.contains(n.id) ? n.copyWith(isRead: true) : n)
            .toList(),
      );
    }
    try {
      await _repo.bulkMarkAsRead(ids);
    } catch (e) {
      await _load();
      rethrow;
    }
  }

  Future<void> deleteNotification(String id) async {
    await _repo.deleteNotification(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(current.where((n) => n.id != id).toList());
    }
  }

  Future<void> bulkDelete(List<String> ids) async {
    await _repo.bulkDelete(ids);
    final current = state.valueOrNull;
    if (current != null) {
      final idSet = ids.toSet();
      state = AsyncValue.data(
          current.where((n) => !idSet.contains(n.id)).toList());
    }
  }
}

final notificationsNotifierProvider = StateNotifierProvider<
    NotificationsNotifier, AsyncValue<List<AppNotification>>>((ref) {
  return NotificationsNotifier(ref.watch(notificationsRepositoryProvider));
});

/// Unread count — useful for badge indicators.
final unreadCountProvider = Provider<int>((ref) {
  final notifications =
      ref.watch(notificationsNotifierProvider).valueOrNull ?? [];
  return notifications.where((n) => !n.isRead).length;
});
