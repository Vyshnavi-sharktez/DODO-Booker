import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/amc/providers/amc_contract_provider.dart';
import '../../features/amc/providers/amc_plans_provider.dart';
import '../../features/booking/services/coupon_providers.dart';
import '../../features/bookings/services/bookings_providers.dart';
import '../../features/notifications/services/notification_providers.dart';
import '../../features/catalog/providers/catalog_providers.dart';
import '../../features/home/services/home_providers.dart';
import '../../features/loyalty/providers/loyalty_providers.dart';
import '../../features/surge_fee/providers/surge_fee_provider.dart';
import '../../features/tax/providers/tax_provider.dart';

/// Manages all Supabase Realtime subscriptions for the customer app.
///
/// Kept alive for the lifetime of the ProviderScope via [realtimeSyncProvider].
///
/// Two channels are maintained:
///   dodo-customer-sync  — shared channel for catalog, config, banners, coupons,
///                         bookings, and broadcast notifications (user_type='customer').
///   dodo-customer-notif-{id} — per-customer channel for personal notifications
///                              filtered by user_id = customerId. Created after auth
///                              via ref.listen(currentCustomerIdProvider, ...).
///
/// Why two channels for notifications?
///   Supabase Realtime evaluates RLS using the connection's JWT. With the anon
///   key (no auth.uid()), an UNFILTERED subscription on `notifications` fails RLS
///   and events are silently dropped. An explicit filter (user_id = X or
///   user_type = 'customer') gives Supabase a concrete row predicate to evaluate,
///   which succeeds under the permissive anon-read RLS on this table.
///
/// Catalog and config callbacks are debounced (300 ms) so that a burst of
/// related events (e.g., a multi-row admin update) collapses into a single
/// invalidation cycle rather than triggering 9+ simultaneous provider
/// rebuilds that saturate Flutter's event loop and delay gesture processing.
///
/// Event → invalidation map:
///   catalog_nodes / catalog_node_relationships /
///   catalog_node_location_restrictions       → _invalidateCatalog() [debounced]
///   tax_settings                             → _invalidateConfig()  [debounced]
///   surge_fee_settings                       → _invalidateConfig()  [debounced]
///   loyalty_settings                         → _invalidateConfig()  [debounced]
///   catalog_node_configs                     → _invalidateConfig()  [debounced]
///   banners                                  → homeBannersProvider
///   coupons                                  → activeCouponsProvider
///   notifications (broadcast, user_type=customer) → notificationsProvider
///   notifications (personal,  user_id=cust)  → notificationsProvider
///   bookings                                 → myBookingsProvider
///   amc_contracts                            → processedBookingsProvider + amcContractProvider + allAmcContractsProvider
class CustomerRealtimeSync {
  final Ref _ref;
  final SupabaseClient _client;
  RealtimeChannel? _channel;
  RealtimeChannel? _notifChannel;
  Timer? _catalogDebounce;
  Timer? _configDebounce;

  CustomerRealtimeSync(this._ref, this._client) {
    _subscribe();
  }

  void _subscribe() {
    _channel = _client
        .channel('dodo-customer-sync')
        // ── Catalog structure + availability + location ──────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'catalog_nodes',
          callback: (_) => _debouncedInvalidateCatalog(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'catalog_node_relationships',
          callback: (_) => _debouncedInvalidateCatalog(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'catalog_node_location_restrictions',
          callback: (_) => _debouncedInvalidateCatalog(),
        )
        // ── Global config tables (tax / surge / loyalty) ─────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tax_settings',
          callback: (_) => _debouncedInvalidateConfig(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'surge_fee_settings',
          callback: (_) => _debouncedInvalidateConfig(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'loyalty_settings',
          callback: (_) => _debouncedInvalidateConfig(),
        )
        // ── Scoped per-node module configs (tax / surge / loyalty / scheduling)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'catalog_node_configs',
          callback: (_) => _debouncedInvalidateConfig(),
        )
        // ── Home banners ─────────────────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'banners',
          callback: (_) => _ref.invalidate(homeBannersProvider),
        )
        // ── Coupon changes (admin creates/updates/deactivates coupons) ────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'coupons',
          callback: (_) => _ref.invalidate(activeCouponsProvider),
        )
        // ── Broadcast notifications (user_type='customer', user_id IS NULL) ───
        // Filtered by user_type so Supabase evaluates a concrete row predicate
        // rather than sending all rows (which fails RLS with the anon key).
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_type',
            value: 'customer',
          ),
          callback: (_) {
            debugPrint('[DODO][CustomerSync] broadcast notification event → invalidating notificationsProvider');
            _ref.invalidate(notificationsProvider);
          },
        )
        // ── Booking status changes (admin updates customer booking) ───────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (_) {
            _ref.invalidate(myBookingsProvider);
            // Refresh contract detail screens — admin approval sets service_date
            // on the booking row, so the visits timeline must re-render.
            _ref.invalidate(amcContractProvider);
          },
        )
        // ── AMC scheduling request resolved (admin approves or rejects) ───────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'amc_scheduling_requests',
          callback: (_) {
            _ref.invalidate(pendingAmcRequestProvider);
            _ref.invalidate(amcContractProvider);
          },
        )
        // ── AMC pause request resolved (admin approves/rejects pause) ─────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'amc_pause_requests',
          callback: (_) {
            _ref.invalidate(pendingAmcPauseRequestProvider);
            _ref.invalidate(amcPauseRequestsForContractProvider);
            _ref.invalidate(allAmcPauseRequestsProvider);
            _ref.invalidate(amcContractProvider);
          },
        )
        // ── AMC resume request resolved (admin approves/rejects resume) ───────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'amc_resume_requests',
          callback: (_) {
            _ref.invalidate(pendingAmcResumeRequestProvider);
            _ref.invalidate(amcResumeRequestsForContractProvider);
            _ref.invalidate(allAmcResumeRequestsProvider);
            _ref.invalidate(amcContractProvider);
          },
        )
        // ── AMC contract status changes (admin approves/rejects cancellation) ─
        // Invalidate both the bookings list (which shows AMC contract cards) and
        // any open contract detail screen so the customer sees the new status
        // immediately when the admin acts on a cancellation request.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'amc_contracts',
          callback: (_) {
            _ref.invalidate(processedBookingsProvider);
            _ref.invalidate(myBookingsProvider);
            _ref.invalidate(amcContractProvider);
            _ref.invalidate(allAmcContractsProvider);
          },
        )
        .subscribe((status, error) {
          debugPrint('[DODO][CustomerSync] shared channel status=$status error=$error');
        });
  }

  // ── Personal notification channel ────────────────────────────────────────────

  void resubscribeNotifications(String? customerId) {
    if (_notifChannel != null) {
      _client.removeChannel(_notifChannel!);
      _notifChannel = null;
    }
    if (customerId == null) return;

    _notifChannel = _client
        .channel('dodo-customer-notif-$customerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: customerId,
          ),
          callback: (_) {
            debugPrint('[DODO][CustomerSync] personal notification INSERT → invalidating notificationsProvider + AMC providers');
            _ref.invalidate(notificationsProvider);
            // Re-fetch AMC state on every personal notification so that
            // admin actions (approve/reject cancellation, schedule visit)
            // are reflected immediately even if the amc_contracts Realtime
            // event was silently dropped by RLS evaluation.
            _ref.invalidate(amcContractProvider);
            _ref.invalidate(allAmcContractsProvider);
            _ref.invalidate(processedBookingsProvider);
            _ref.invalidate(myBookingsProvider);
            _ref.invalidate(pendingAmcRequestProvider);
            _ref.invalidate(pendingAmcPauseRequestProvider);
            _ref.invalidate(pendingAmcResumeRequestProvider);
            _ref.invalidate(amcPauseRequestsForContractProvider);
            _ref.invalidate(amcResumeRequestsForContractProvider);
            _ref.invalidate(allAmcPauseRequestsProvider);
            _ref.invalidate(allAmcResumeRequestsProvider);
          },
        )
        .subscribe((status, error) {
          debugPrint('[DODO][CustomerSync] notif channel status=$status error=$error');
        });
    debugPrint('[DODO][CustomerSync] notification channel subscribed for customer=$customerId');
  }

  // Collapse rapid catalog events into one invalidation cycle.
  // Without debouncing, a multi-table admin update fires several callbacks
  // within milliseconds, each invalidating 9 providers and triggering a
  // large widget rebuild wave that blocks Flutter's event loop on web.
  void _debouncedInvalidateCatalog() {
    _catalogDebounce?.cancel();
    _catalogDebounce = Timer(const Duration(milliseconds: 300), _invalidateCatalog);
  }

  void _debouncedInvalidateConfig() {
    _configDebounce?.cancel();
    _configDebounce = Timer(const Duration(milliseconds: 300), _invalidateConfig);
  }

  void _invalidateCatalog() {
    _ref.invalidate(rootCatalogNodesProvider);
    _ref.invalidate(catalogNodeChildrenProvider);
    _ref.invalidate(catalogNodeProvider);
    _ref.invalidate(catalogNodeFaqsProvider);
    _ref.invalidate(nodeAvailabilityProvider);
    _ref.invalidate(featuredCatalogNodesProvider);
    _ref.invalidate(featuredServicesProvider);
    _ref.invalidate(popularServicesProvider);
    _ref.invalidate(trendingServicesProvider);
    _ref.invalidate(newServicesProvider);
  }

  void _invalidateConfig() {
    _ref.invalidate(taxSettingsProvider);
    _ref.invalidate(resolvedTaxProvider);
    _ref.invalidate(surgeFeeSettingsProvider);
    _ref.invalidate(resolvedSurgeFeeProvider);
    _ref.invalidate(loyaltySettingsProvider);
    _ref.invalidate(resolvedLoyaltyConfigProvider);
    _ref.invalidate(customerLoyaltyProvider);
  }

  /// Called by the lifecycle observer on app resume after an extended pause.
  /// Refetches everything that Realtime may have missed during the gap.
  void refetchAll() {
    _invalidateCatalog();
    _invalidateConfig();
    _ref.invalidate(myBookingsProvider);
    _ref.invalidate(processedBookingsProvider);
    _ref.invalidate(amcContractProvider);
    _ref.invalidate(allAmcContractsProvider);
    _ref.invalidate(homeBannersProvider);
    _ref.invalidate(activeCouponsProvider);
    _ref.invalidate(notificationsProvider);
    _ref.invalidate(pendingAmcRequestProvider);
    _ref.invalidate(pendingAmcPauseRequestProvider);
    _ref.invalidate(pendingAmcResumeRequestProvider);
    _ref.invalidate(amcPauseRequestsForContractProvider);
    _ref.invalidate(amcResumeRequestsForContractProvider);
    _ref.invalidate(allAmcPauseRequestsProvider);
    _ref.invalidate(allAmcResumeRequestsProvider);
  }

  void dispose() {
    _catalogDebounce?.cancel();
    _configDebounce?.cancel();
    if (_channel != null) _client.removeChannel(_channel!);
    if (_notifChannel != null) _client.removeChannel(_notifChannel!);
  }
}

final realtimeSyncProvider = Provider<CustomerRealtimeSync>((ref) {
  final sync = CustomerRealtimeSync(ref, Supabase.instance.client);
  ref.onDispose(sync.dispose);

  // React to customer ID changes (sign-in, sign-out, session restore) and
  // (re)create the personal notification channel accordingly.  fireImmediately
  // ensures the channel is set up even if the customer is already authenticated
  // when this provider first runs.
  ref.listen<AsyncValue<String?>>(
    currentCustomerIdProvider,
    (_, next) => next.whenData((id) => sync.resubscribeNotifications(id)),
    fireImmediately: true,
  );

  return sync;
});
