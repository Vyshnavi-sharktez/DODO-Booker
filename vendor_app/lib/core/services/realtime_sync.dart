import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/domain/entities/vendor_user.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/bookings/presentation/providers/bookings_provider.dart';
import '../../features/dashboard/presentation/providers/dashboard_provider.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';
import '../../features/subscription/presentation/providers/subscription_provider.dart';

/// Manages all Supabase Realtime subscriptions for the vendor app.
///
/// Two channels are maintained:
///   bookings  — PostgresChangeEvent.all  — invalidates booking + dashboard providers.
///   notifications — PostgresChangeEvent.insert — invalidates vendorNotificationsProvider.
///
/// The bookings channel carries no user-level filter (handled by query-level
/// filtering in the providers). The notifications channel is filtered by
/// `user_id = vendorId` to avoid waking up on other vendors' events.
///
/// The channel is created under the Supabase anon key (this app uses custom
/// phone auth — there is no Supabase Auth session/JWT).  The `_authSub`
/// listener handles JWT rotation / reconnection when Supabase Auth IS in use
/// and is retained for future compatibility, but does not fire under the
/// current custom-auth implementation.
///
/// Notifications channel lifecycle:
///   vendorRealtimeSyncProvider calls ref.listen(currentVendorUserProvider, ...)
///   with fireImmediately: true so the channel is created as soon as the
///   vendor ID is known (including on the initial build if already logged in)
///   and torn down on sign-out.
class VendorRealtimeSync {
  final Ref _ref;
  final SupabaseClient _client;

  RealtimeChannel? _bookingsChannel;
  RealtimeChannel? _notifChannel;
  RealtimeChannel? _subscriptionChannel;
  RealtimeChannel? _settingsChannel;
  StreamSubscription<AuthState>? _authSub;

  VendorRealtimeSync(this._ref, this._client) {
    _subscribeBookings();
    _subscribeSettings();
    _authSub = _client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if ((event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.initialSession ||
              event == AuthChangeEvent.tokenRefreshed) &&
          data.session != null) {
        debugPrint('[DODO][VendorSync] auth=$event — re-subscribing channels');
        _resubscribeBookings();
        // Re-subscribe notifications with the vendor ID currently in state.
        final vendorId = _ref.read(currentVendorUserProvider)?.id;
        resubscribeNotifications(vendorId);
      }
    });
  }

  // ── Bookings ────────────────────────────────────────────────────────────────

  void _subscribeBookings() {
    _bookingsChannel = _client
        .channel('dodo-vendor-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (payload) {
            debugPrint('[DODO][VendorSync] bookings event: '
                'type=${payload.eventType} '
                'old.vendor_id=${payload.oldRecord["vendor_id"]} '
                'new.vendor_id=${payload.newRecord["vendor_id"]}');
            _invalidateBookings();
          },
        )
        .subscribe((status, error) {
          debugPrint('[DODO][VendorSync] bookings channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] bookings channel subscribed');
  }

  void _resubscribeBookings() {
    if (_bookingsChannel != null) {
      _client.removeChannel(_bookingsChannel!);
      _bookingsChannel = null;
    }
    _subscribeBookings();
  }

  void _invalidateBookings() {
    debugPrint('[DODO][VendorSync] invalidating vendorBookingsProvider + dashboardStatsProvider');
    _ref.invalidate(vendorBookingsProvider);
    _ref.invalidate(dashboardStatsProvider);
  }

  // ── Settings ────────────────────────────────────────────────────────────────
  //
  // Listens for UPDATE events on the settings table so that when the admin
  // changes subscription_enabled (or any other setting), the vendor app
  // invalidates its cached settings immediately — no manual refresh needed.
  //
  // No filter is applied: settings changes are infrequent and global; any
  // updated row should trigger a re-fetch of the subscription settings.

  void _subscribeSettings() {
    _settingsChannel = _client
        .channel('dodo-vendor-settings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'settings',
          callback: (payload) {
            debugPrint(
                '[DODO][VendorSync] settings ${payload.eventType} → '
                'invalidating subscriptionSettingsProvider');
            _ref.invalidate(subscriptionSettingsProvider);
          },
        )
        .subscribe((status, error) {
          debugPrint(
              '[DODO][VendorSync] settings channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] settings channel subscribed');
  }

  // ── Subscription ────────────────────────────────────────────────────────────

  void resubscribeSubscription(String? vendorId) {
    if (_subscriptionChannel != null) {
      _client.removeChannel(_subscriptionChannel!);
      _subscriptionChannel = null;
    }
    if (vendorId == null) return;

    _subscriptionChannel = _client
        .channel('dodo-vendor-sub-$vendorId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vendor_subscriptions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'vendor_id',
            value: vendorId,
          ),
          callback: (_) {
            debugPrint('[DODO][VendorSync] vendor_subscriptions change → '
                'invalidating mySubscriptionProvider');
            _ref.invalidate(mySubscriptionProvider);
          },
        )
        .subscribe((status, error) {
          debugPrint(
              '[DODO][VendorSync] subscription channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] subscription channel subscribed for vendor=$vendorId');
  }

  // ── Notifications ───────────────────────────────────────────────────────────

  void resubscribeNotifications(String? vendorId) {
    if (_notifChannel != null) {
      _client.removeChannel(_notifChannel!);
      _notifChannel = null;
    }
    if (vendorId == null) return;

    _notifChannel = _client
        .channel('dodo-vendor-notif-$vendorId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: vendorId,
          ),
          callback: (_) {
            debugPrint('[DODO][VendorSync] notification INSERT → invalidating vendorNotificationsProvider');
            _ref.invalidate(vendorNotificationsProvider);
          },
        )
        .subscribe((status, error) {
          debugPrint('[DODO][VendorSync] notif channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] notification channel subscribed for vendor=$vendorId');
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Called by the lifecycle observer on resume after an extended pause.
  void refetchAll() {
    _invalidateBookings();
    _ref.invalidate(subscriptionSettingsProvider);
  }

  void dispose() {
    _authSub?.cancel();
    if (_bookingsChannel != null) _client.removeChannel(_bookingsChannel!);
    if (_notifChannel != null) _client.removeChannel(_notifChannel!);
    if (_subscriptionChannel != null) _client.removeChannel(_subscriptionChannel!);
    if (_settingsChannel != null) _client.removeChannel(_settingsChannel!);
  }
}

final vendorRealtimeSyncProvider = Provider<VendorRealtimeSync>((ref) {
  final sync = VendorRealtimeSync(ref, Supabase.instance.client);
  ref.onDispose(sync.dispose);

  // React to vendor user changes so the notification channel is created/destroyed
  // at the right time. fireImmediately:true covers the case where the vendor is
  // already authenticated when this provider first runs (e.g., hot-restart or
  // if the provider is lazily initialised after session restore).
  ref.listen<VendorUser?>(
    currentVendorUserProvider,
    (_, user) {
      sync.resubscribeNotifications(user?.id);
      sync.resubscribeSubscription(user?.id);
    },
    fireImmediately: true,
  );

  return sync;
});
