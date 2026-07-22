import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

/// Maintains a Supabase Realtime subscription for vendor notification INSERTs.
/// When a new row arrives for this vendor, invalidates [vendorNotificationsProvider]
/// so the UI refreshes automatically without polling.
///
/// Non-autoDispose — kept alive for the ProviderScope lifetime.
/// Rebuilds automatically when [currentVendorUserProvider] changes (sign-in / sign-out).
final vendorNotificationsRealtimeProvider = Provider<void>((ref) {
  final user = ref.watch(currentVendorUserProvider);
  if (user == null) return;

  final client = ref.read(supabaseClientProvider);
  final channel = client
      .channel('vendor-notif-${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: (_) {
          debugPrint('[DODO][VendorNotif] INSERT → invalidating vendorNotificationsProvider');
          ref.invalidate(vendorNotificationsProvider);
        },
      )
      .subscribe((status, error) {
        debugPrint('[DODO][VendorNotif] channel status=$status error=$error');
      });

  ref.onDispose(() => client.removeChannel(channel));
});
