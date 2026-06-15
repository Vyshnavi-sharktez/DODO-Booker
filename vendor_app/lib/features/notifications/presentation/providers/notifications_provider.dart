import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/notifications_repository.dart';
import '../../domain/models/vendor_notification.dart';

export '../../data/notifications_repository.dart';

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
