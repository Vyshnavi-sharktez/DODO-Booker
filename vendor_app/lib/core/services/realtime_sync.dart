import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/bookings/presentation/providers/bookings_provider.dart';
import '../../features/dashboard/presentation/providers/dashboard_provider.dart';

/// Manages Supabase Realtime subscriptions for the vendor app.
///
/// Kept alive for the lifetime of the ProviderScope via [vendorRealtimeSyncProvider].
///
/// The channel is first created during [VendorApp.initState] — before the vendor
/// has authenticated.  Supabase Realtime evaluates RLS using the JWT that was
/// active when the channel was subscribed; updating the JWT later does not
/// retroactively re-evaluate existing channel filters on the server side.
/// To ensure the channel carries the vendor's authenticated JWT (and therefore
/// receives events gated by `auth.uid() = vendor_id`), the channel is
/// re-subscribed on [AuthChangeEvent.signedIn], [AuthChangeEvent.initialSession]
/// (saved session restored on app open — the common production path), and
/// [AuthChangeEvent.tokenRefreshed] (JWT rotation mid-session).
///
/// Event → action map:
///   bookings INSERT/UPDATE/DELETE → invalidate vendorBookingsProvider + dashboardStatsProvider
class VendorRealtimeSync {
  final Ref _ref;
  final SupabaseClient _client;
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;

  VendorRealtimeSync(this._ref, this._client) {
    _subscribe();
    _authSub = _client.auth.onAuthStateChange.listen((data) {
      // signedIn    → vendor explicitly logs in (fresh session).
      // initialSession → saved session restored on app open (pre-authenticated
      //                  vendor). This is the common production case and was
      //                  previously unhandled, causing the channel to remain
      //                  subscribed with the anon JWT so RLS dropped all events.
      // tokenRefreshed → JWT rotated mid-session; channel must re-auth or
      //                  events stop arriving after the old token expires.
      final event = data.event;
      if ((event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.initialSession ||
              event == AuthChangeEvent.tokenRefreshed) &&
          data.session != null) {
        debugPrint('[DODO][VendorSync] auth=$event — re-subscribing with vendor JWT');
        _resubscribe();
      }
    });
  }

  void _subscribe() {
    _channel = _client
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
          debugPrint('[DODO][VendorSync] channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] channel subscribed');
  }

  void _resubscribe() {
    if (_channel != null) {
      _client.removeChannel(_channel!);
      _channel = null;
    }
    _subscribe();
  }

  void _invalidateBookings() {
    debugPrint('[DODO][VendorSync] invalidating vendorBookingsProvider + dashboardStatsProvider');
    _ref.invalidate(vendorBookingsProvider);
    _ref.invalidate(dashboardStatsProvider);
  }

  /// Called by the lifecycle observer on resume after an extended pause.
  void refetchAll() => _invalidateBookings();

  void dispose() {
    _authSub?.cancel();
    if (_channel != null) _client.removeChannel(_channel!);
  }
}

final vendorRealtimeSyncProvider = Provider<VendorRealtimeSync>((ref) {
  final sync = VendorRealtimeSync(ref, Supabase.instance.client);
  ref.onDispose(sync.dispose);
  return sync;
});
