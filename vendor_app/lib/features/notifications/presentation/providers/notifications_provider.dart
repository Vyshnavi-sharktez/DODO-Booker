import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/notifications_repository.dart';
import '../../domain/models/vendor_notification.dart';

export '../../data/notifications_repository.dart';
export '../../domain/models/vendor_notification.dart';

/// Provided at startup via ProviderScope override so it is always ready
/// synchronously — no async race window.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider in ProviderScope'),
);

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(supabaseClientProvider)),
);

/// Fetches the authenticated vendor's notifications, newest first.
/// Auto-refreshes when the current vendor changes.
final vendorNotificationsProvider =
    FutureProvider.autoDispose<List<VendorNotification>>((ref) {
  final user = ref.watch(currentVendorUserProvider);
  if (user == null) return Future.value([]);
  return ref
      .read(notificationsRepositoryProvider)
      .fetchNotifications(user.id);
});

/// Unread badge count — safe to watch from the navigation shell.
final vendorUnreadCountProvider = Provider<int>((ref) {
  return ref.watch(vendorNotificationsProvider).when(
        data: (list) => list.where((n) => !n.isRead).length,
        loading: () => 0,
        error: (e, st) => 0,
      );
});

/// Tracks dispatch notification IDs that have already been presented.
/// Reads from SharedPreferences synchronously in build() (prefs are pre-loaded
/// at startup) so there is no async race with the incoming notifications stream.
class _HandledDispatchNotifIdsNotifier extends Notifier<Set<String>> {
  static const _keyPrefix = 'dodo_handled_dispatch_notifs_';

  @override
  Set<String> build() {
    final vendorId = ref.watch(currentVendorUserProvider)?.id;
    if (vendorId == null) return {};
    final prefs = ref.read(sharedPreferencesProvider);
    final stored = prefs.getStringList('$_keyPrefix$vendorId') ?? [];
    return Set<String>.from(stored);
  }

  Future<void> add(String id) async {
    state = {...state, id};
    final vendorId = ref.read(currentVendorUserProvider)?.id;
    if (vendorId == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList('$_keyPrefix$vendorId', state.toList());
  }
}

final handledDispatchNotifIdsProvider =
    NotifierProvider<_HandledDispatchNotifIdsNotifier, Set<String>>(
  _HandledDispatchNotifIdsNotifier.new,
);
