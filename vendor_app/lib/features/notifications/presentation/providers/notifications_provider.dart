import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/notifications_repository.dart';
import '../../domain/models/vendor_notification.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(supabaseClientProvider)),
);

class NotificationsNotifier
    extends StateNotifier<AsyncValue<List<VendorNotification>>> {
  NotificationsNotifier(this._repo) : super(const AsyncValue.loading());

  final NotificationsRepository _repo;

  Future<void> load(String vendorId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.fetchNotifications(vendorId),
    );
  }

  Future<void> markAsRead(String id) async {}

  Future<void> markAllAsRead(String vendorId) async {}

  Future<void> delete(String id) async {}

  int get unreadCount =>
      state.valueOrNull?.where((n) => !n.isRead).length ?? 0;
}

final notificationsNotifierProvider = StateNotifierProvider<
    NotificationsNotifier, AsyncValue<List<VendorNotification>>>(
  (ref) =>
      NotificationsNotifier(ref.watch(notificationsRepositoryProvider)),
);

final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsNotifierProvider).valueOrNull
          ?.where((n) => !n.isRead)
          .length ??
      0,
);
