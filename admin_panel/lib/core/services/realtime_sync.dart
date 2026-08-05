import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/application/providers/auth_provider.dart';
import '../../features/bookings/application/providers/bookings_providers.dart';
import '../../features/bookings/application/providers/dispatch_providers.dart';
import '../../features/notifications/application/providers/notifications_providers.dart';
import '../../features/vendors/application/providers/vendors_providers.dart';

/// Manages Supabase Realtime subscriptions for the admin panel.
///
/// Kept alive for the lifetime of the ProviderScope via [adminRealtimeSyncProvider].
///
/// Event → action map:
///   bookings INSERT/UPDATE/DELETE        → bookingsNotifierProvider.refresh()
///   customer_reviews INSERT/UPDATE/DELETE → bookingsNotifierProvider.refresh()
///     (reviews are joined into Booking.fromMap; a full refresh picks up the
///      new review without needing a separate provider)
class AdminRealtimeSync {
  final Ref _ref;
  final SupabaseClient _client;
  RealtimeChannel? _channel;

  AdminRealtimeSync(this._ref, this._client) {
    _subscribe();
    _ref.watch(dispatchEscalationTimerProvider);
  }

  void _subscribe() {
    _channel = _client
        .channel('dodo-admin-sync')
        // Customer creates booking → admin list refreshes automatically.
        // Admin updates status   → in-place patch already done by the notifier;
        //   Realtime fires the UPDATE event and triggers a full refresh as safety net.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (_) => _refreshBookings(),
        )
        // Customer submits/edits a review → admin bookings list rating column updates.
        // Booking.fromMap joins customer_reviews!booking_id, so a full refresh
        // picks up the new review data.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'customer_reviews',
          callback: (_) => _refreshBookings(),
        )
        // Vendor toggles online/offline → assignment dialog reflects new status
        // immediately without admin needing to refresh.
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'vendors',
          callback: (_) => _refreshVendors(),
        )
        // Admin notification inserted (e.g. when vendor accepts booking)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _refreshNotifications(),
        )
        .subscribe();
  }

  void _refreshBookings() {
    _ref.read(bookingsNotifierProvider.notifier).refresh();
  }

  void _refreshVendors() {
    _ref.read(vendorsNotifierProvider.notifier).refresh();
  }

  void _refreshNotifications() {
    _ref.read(notificationsNotifierProvider.notifier).refresh();
  }

  /// Called by the lifecycle observer on admin panel resume after a long pause.
  void refetchAll() {
    _refreshBookings();
  }

  void dispose() {
    if (_channel != null) _client.removeChannel(_channel!);
  }
}

final adminRealtimeSyncProvider = Provider<AdminRealtimeSync>((ref) {
  final client = ref.read(supabaseClientProvider);
  final sync = AdminRealtimeSync(ref, client);
  ref.onDispose(sync.dispose);
  return sync;
});
