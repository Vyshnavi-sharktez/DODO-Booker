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
import '../../features/home/services/landing_page_sections_provider.dart';
import '../../features/loyalty/providers/loyalty_providers.dart';
import '../../features/refund_queries/services/refund_queries_providers.dart';
import '../../features/surge_fee/providers/surge_fee_provider.dart';
import '../../features/tax/providers/tax_provider.dart';
import '../../features/support/services/support_chat_providers.dart';
import '../../features/warranties/services/warranty_providers.dart';

/// Manages all Supabase Realtime subscriptions for the customer app.
///
/// Kept alive for the lifetime of the ProviderScope via [realtimeSyncProvider].
///
/// Two channels are maintained:
///   dodo-customer-sync  — shared channel for catalog, config, banners, coupons,
///                         bookings, AMC, refunds, warranties, and broadcast
///                         notifications (user_type='customer').
///   dodo-customer-notif-{id} — per-customer channel for personal notifications,
///                              refund updates, loyalty changes, and warranty
///                              status changes filtered by customer_id. Created
///                              after auth via ref.listen(currentCustomerIdProvider).
///
/// Why two channels for notifications?
///   Supabase Realtime evaluates RLS using the connection's JWT. With the anon
///   key (no auth.uid()), an UNFILTERED subscription on `notifications` fails RLS
///   and events are silently dropped. An explicit filter (user_id = X or
///   user_type = 'customer') gives Supabase a concrete row predicate to evaluate,
///   which succeeds under the permissive anon-read RLS on this table.
///
/// Catalog and config callbacks are debounced (300 ms) so that a burst of
/// related events collapses into a single invalidation cycle.
///
/// Event → invalidation map (shared channel):
///   catalog_nodes / catalog_node_relationships /
///   catalog_node_location_restrictions       → _invalidateCatalog() [debounced]
///   tax_settings / surge_fee_settings /
///   loyalty_settings / catalog_node_configs  → _invalidateConfig()  [debounced]
///   banners                                  → homeBannersProvider
///   coupons                                  → activeCouponsProvider
///   landing_page_sections                    → landingPageSectionsProvider
///   notifications (broadcast, user_type=customer) → notificationsProvider
///   bookings                                 → myBookingsProvider + amcContractProvider
///   amc_contracts                            → processedBookingsProvider + amcContractProvider + allAmcContractsProvider
///   amc_scheduling_requests                  → pendingAmcRequestProvider + amcContractProvider
///   amc_pause_requests                       → pause request + contract providers
///   amc_resume_requests                      → resume request + contract providers
///
/// Event → invalidation map (personal channel, filtered by customer_id):
///   notifications INSERT                     → notificationsProvider + AMC + support + refund + loyalty
///   refund_requests INSERT/UPDATE            → myRefundQueriesProvider + refundQueryDetailProvider
///   refund_status_history INSERT             → myRefundQueriesProvider + refundQueryDetailProvider
///   refund_messages INSERT                   → refundQueryDetailProvider
///   loyalty_transactions INSERT              → customerLoyaltyProvider + loyaltyTransactionsProvider
///   customer_loyalty UPDATE                  → customerLoyaltyProvider
///   service_warranties INSERT/UPDATE         → customerWarrantiesProvider + bookingWarrantyProvider
class CustomerRealtimeSync {
  final Ref _ref;
  final SupabaseClient _client;
  RealtimeChannel? _channel;
  RealtimeChannel? _notifChannel;
  Timer? _catalogDebounce;
  Timer? _configDebounce;

  // Guard: only recreate personal channel when customer ID actually changes.
  String? _activeNotifCustomerId;

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
        // ── Scoped per-node module configs ───────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'catalog_node_configs',
          callback: (_) => _debouncedInvalidateConfig(),
        )
        // ── Landing page CMS publish events ──────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'landing_page_sections',
          callback: (_) => _ref.invalidate(landingPageSectionsProvider),
        )
        // ── Home banners ─────────────────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'banners',
          callback: (_) => _ref.invalidate(homeBannersProvider),
        )
        // ── Coupon changes ────────────────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'coupons',
          callback: (_) => _ref.invalidate(activeCouponsProvider),
        )
        // ── Broadcast notifications (user_type='customer') ───────────────────
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
            debugPrint('[DODO][CustomerSync] broadcast notification → invalidating notificationsProvider');
            _ref.invalidate(notificationsProvider);
          },
        )
        // ── Booking status changes ────────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (_) {
            _ref.invalidate(myBookingsProvider);
            _ref.invalidate(amcContractProvider);
          },
        )
        // ── AMC scheduling request resolved ───────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'amc_scheduling_requests',
          callback: (_) {
            _ref.invalidate(pendingAmcRequestProvider);
            _ref.invalidate(amcContractProvider);
          },
        )
        // ── AMC pause request resolved ────────────────────────────────────────
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
        // ── AMC resume request resolved ───────────────────────────────────────
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
        // ── AMC contract status changes ───────────────────────────────────────
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

  // ── Personal notification + data channel ─────────────────────────────────────
  //
  // Created after sign-in and destroyed on sign-out. Filtered by customer_id
  // so RLS evaluation succeeds under the anon key.
  //
  // Same-value guard: if the incoming customerId equals the currently active
  // one, we skip teardown and recreation to prevent channel churn on repeated
  // auth-state emissions (e.g., session restore firing multiple events).

  void resubscribeNotifications(String? customerId) {
    // Skip if same ID — prevents churn on repeated auth-state emissions.
    if (customerId == _activeNotifCustomerId) return;
    _activeNotifCustomerId = customerId;

    if (_notifChannel != null) {
      _client.removeChannel(_notifChannel!);
      _notifChannel = null;
    }
    if (customerId == null) return;

    _notifChannel = _client
        .channel('dodo-customer-notif-$customerId')
        // ── Personal notifications ─────────────────────────────────────────
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
            debugPrint('[DODO][CustomerSync] personal notification INSERT → invalidating all relevant providers');
            _ref.invalidate(notificationsProvider);
            _ref.invalidate(supportConversationProvider);
            // Safety-net re-fetch for AMC state (covers RLS-dropped events).
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
            // Also refresh refund queries on notification (safety net).
            _ref.invalidate(myRefundQueriesProvider);
          },
        )
        // ── Refund request status changes ──────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'refund_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: customerId,
          ),
          callback: (payload) {
            debugPrint('[DODO][CustomerSync] refund_requests change → invalidating refund providers');
            _ref.invalidate(myRefundQueriesProvider);
            // Invalidate all autoDispose family instances by invalidating the family.
            _ref.invalidate(refundQueryDetailProvider);
          },
        )
        // ── Refund status history (timeline) ──────────────────────────────
        // Supabase Realtime filter on refund_status_history requires joining
        // through refund_requests, which is not supported. Subscribe without
        // a filter and trust RLS to scope visibility to the customer's own rows.
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'refund_status_history',
          callback: (_) {
            debugPrint('[DODO][CustomerSync] refund_status_history INSERT → invalidating refund providers');
            _ref.invalidate(myRefundQueriesProvider);
            _ref.invalidate(refundQueryDetailProvider);
          },
        )
        // ── Refund messages (new admin reply) ──────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'refund_messages',
          callback: (_) {
            debugPrint('[DODO][CustomerSync] refund_messages INSERT → invalidating refundQueryDetailProvider');
            _ref.invalidate(refundQueryDetailProvider);
          },
        )
        // ── Loyalty transactions (points earned or redeemed) ───────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'loyalty_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: customerId,
          ),
          callback: (_) {
            debugPrint('[DODO][CustomerSync] loyalty_transactions INSERT → invalidating loyalty providers');
            _ref.invalidate(customerLoyaltyProvider);
            _ref.invalidate(loyaltyTransactionsProvider);
          },
        )
        // ── Customer loyalty balance (direct update e.g. admin adjustment) ─
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'customer_loyalty',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: customerId,
          ),
          callback: (_) {
            debugPrint('[DODO][CustomerSync] customer_loyalty UPDATE → invalidating customerLoyaltyProvider');
            _ref.invalidate(customerLoyaltyProvider);
          },
        )
        // ── Warranty status changes ────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_warranties',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: customerId,
          ),
          callback: (_) {
            debugPrint('[DODO][CustomerSync] service_warranties change → invalidating warranty providers');
            _ref.invalidate(customerWarrantiesProvider);
            _ref.invalidate(bookingWarrantyProvider);
            _ref.invalidate(warrantyByIdProvider);
          },
        )
        .subscribe((status, error) {
          debugPrint('[DODO][CustomerSync] notif channel status=$status error=$error');
        });
    debugPrint('[DODO][CustomerSync] personal channel subscribed for customer=$customerId');
  }

  // ── Debounced invalidation helpers ───────────────────────────────────────────

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
  void refetchAll() {
    _invalidateCatalog();
    _invalidateConfig();
    _ref.invalidate(landingPageSectionsProvider);
    _ref.invalidate(myBookingsProvider);
    _ref.invalidate(processedBookingsProvider);
    _ref.invalidate(amcContractProvider);
    _ref.invalidate(allAmcContractsProvider);
    _ref.invalidate(homeBannersProvider);
    _ref.invalidate(activeCouponsProvider);
    _ref.invalidate(notificationsProvider);
    _ref.invalidate(supportConversationProvider);
    _ref.invalidate(pendingAmcRequestProvider);
    _ref.invalidate(pendingAmcPauseRequestProvider);
    _ref.invalidate(pendingAmcResumeRequestProvider);
    _ref.invalidate(amcPauseRequestsForContractProvider);
    _ref.invalidate(amcResumeRequestsForContractProvider);
    _ref.invalidate(allAmcPauseRequestsProvider);
    _ref.invalidate(allAmcResumeRequestsProvider);
    _ref.invalidate(myRefundQueriesProvider);
    _ref.invalidate(refundQueryDetailProvider);
    _ref.invalidate(customerLoyaltyProvider);
    _ref.invalidate(loyaltyTransactionsProvider);
    _ref.invalidate(customerWarrantiesProvider);
    _ref.invalidate(bookingWarrantyProvider);
    _ref.invalidate(warrantyByIdProvider);
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
  // (re)create the personal channel accordingly. fireImmediately ensures the
  // channel is set up even if the customer is already authenticated when this
  // provider first runs. The same-value guard inside resubscribeNotifications
  // prevents unnecessary channel churn on repeated emissions of the same ID.
  ref.listen<AsyncValue<String?>>(
    currentCustomerIdProvider,
    (_, next) => next.whenData((id) => sync.resubscribeNotifications(id)),
    fireImmediately: true,
  );

  return sync;
});
