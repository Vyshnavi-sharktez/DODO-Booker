import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
/// All subscriptions share a single channel to avoid duplicate connections.
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
///   notifications                            → notificationsProvider (+ unreadCountProvider)
///   bookings                                 → myBookingsProvider
class CustomerRealtimeSync {
  final Ref _ref;
  final SupabaseClient _client;
  RealtimeChannel? _channel;
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
        // ── Notifications (admin sends personal or broadcast notifications) ────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _ref.invalidate(notificationsProvider),
        )
        // ── Booking status changes (admin updates customer booking) ───────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (_) => _ref.invalidate(myBookingsProvider),
        )
        .subscribe();
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
    _ref.invalidate(homeBannersProvider);
    _ref.invalidate(activeCouponsProvider);
    _ref.invalidate(notificationsProvider);
  }

  void dispose() {
    _catalogDebounce?.cancel();
    _configDebounce?.cancel();
    if (_channel != null) _client.removeChannel(_channel!);
  }
}

final realtimeSyncProvider = Provider<CustomerRealtimeSync>((ref) {
  final sync = CustomerRealtimeSync(ref, Supabase.instance.client);
  ref.onDispose(sync.dispose);
  return sync;
});
