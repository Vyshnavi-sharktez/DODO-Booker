import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import 'notification_service.dart';
import '../models/notification_model.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

/// Personal + broadcast notifications for the current customer.
/// Returns empty list when unauthenticated. Re-fetches on auth change.
final notificationsProvider =
    FutureProvider<List<NotificationModel>>((ref) async {
  final isAuth = ref.watch(isAuthenticatedProvider);
  if (!isAuth) return [];
  return ref.read(notificationServiceProvider).fetchNotifications();
});

/// Count of unread notifications — used for badges in header and profile.
final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).when(
        data: (list) => list.where((n) => !n.isRead).length,
        loading: () => 0,
        error: (e, _) => 0,
      );
});
