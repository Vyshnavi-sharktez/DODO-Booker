import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/domain/entities/vendor_user.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/bookings/presentation/providers/bookings_provider.dart';
import '../../features/dashboard/presentation/providers/dashboard_provider.dart';
import '../../features/documents/presentation/providers/documents_provider.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';
import '../../features/services/presentation/providers/services_provider.dart';
import '../../features/subscription/presentation/providers/subscription_provider.dart';
import '../../features/wallet/presentation/providers/wallet_provider.dart';

/// Manages all Supabase Realtime subscriptions for the vendor app.
///
/// Channels maintained:
///   dodo-vendor-sync      — bookings (all events).
///   dodo-vendor-settings  — settings (all events).
///   dodo-vendor-sub-{id}  — vendor_subscriptions scoped to this vendor.
///   dodo-vendor-notif-{id} — notifications INSERT scoped to this vendor.
///   dodo-vendor-wallet-{id} — vendor_wallets + wallet_transactions scoped to this vendor.
///   dodo-vendor-docs-{id}  — vendor_documents scoped to this vendor.
///   dodo-vendor-catalog    — catalog_nodes (all events, no filter needed — vendor
///                            browses the global catalog).
///
/// Note: this app uses custom phone auth, not Supabase Auth. The _authSub
/// listener that previously watched Supabase Auth state changes was dead code
/// (never fired) and has been removed to avoid confusion.
///
/// Per-vendor channels (wallet, docs, notif, sub) are lifecycle-managed via
/// ref.listen(currentVendorUserProvider) with fireImmediately:true.
/// Same-value guards prevent channel churn on repeated emissions of the same ID.
class VendorRealtimeSync {
  final Ref _ref;
  final SupabaseClient _client;

  RealtimeChannel? _bookingsChannel;
  RealtimeChannel? _notifChannel;
  RealtimeChannel? _subscriptionChannel;
  RealtimeChannel? _settingsChannel;
  RealtimeChannel? _walletChannel;
  RealtimeChannel? _docsChannel;
  RealtimeChannel? _catalogChannel;

  // Same-value guards to prevent channel churn.
  String? _activeNotifVendorId;
  String? _activeWalletVendorId;
  String? _activeDocsVendorId;
  String? _activeSubVendorId;

  VendorRealtimeSync(this._ref, this._client) {
    _subscribeBookings();
    _subscribeSettings();
    _subscribeCatalog();
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

  void _invalidateBookings() {
    debugPrint('[DODO][VendorSync] invalidating vendorBookingsProvider + dashboardStatsProvider');
    _ref.invalidate(vendorBookingsProvider);
    _ref.invalidate(dashboardStatsProvider);
    _ref.invalidate(vendorNotificationsProvider);
  }

  // ── Settings ────────────────────────────────────────────────────────────────

  void _subscribeSettings() {
    _settingsChannel = _client
        .channel('dodo-vendor-settings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'settings',
          callback: (payload) {
            debugPrint('[DODO][VendorSync] settings ${payload.eventType} → '
                'invalidating subscriptionSettingsProvider');
            _ref.invalidate(subscriptionSettingsProvider);
          },
        )
        .subscribe((status, error) {
          debugPrint('[DODO][VendorSync] settings channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] settings channel subscribed');
  }

  // ── Global catalog (vendor browses global service catalog) ──────────────────
  //
  // No vendor_id filter — vendor browsing catalog_nodes is a global operation.
  // When admin edits catalog nodes, the vendor's services list and trending
  // services auto-update without requiring a pull-to-refresh.

  void _subscribeCatalog() {
    _catalogChannel = _client
        .channel('dodo-vendor-catalog')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'catalog_nodes',
          callback: (_) {
            debugPrint('[DODO][VendorSync] catalog_nodes change → invalidating catalog + services providers');
            _ref.invalidate(catalogServicesProvider);
            _ref.invalidate(catalogParentMapProvider);
            _ref.invalidate(vendorTrendingServicesProvider);
          },
        )
        // Also watch amc_plans — when admin updates plan pricing/features,
        // vendor's plan-browsing screen updates without a manual refresh.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'amc_plans',
          callback: (_) {
            debugPrint('[DODO][VendorSync] amc_plans change → invalidating vendorServicesProvider');
            // No dedicated AMC plans provider in vendor app; invalidate
            // the general services provider as it includes plan metadata.
            _ref.invalidate(catalogServicesProvider);
          },
        )
        .subscribe((status, error) {
          debugPrint('[DODO][VendorSync] catalog channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] catalog channel subscribed');
  }

  // ── Subscription ────────────────────────────────────────────────────────────

  void resubscribeSubscription(String? vendorId) {
    if (vendorId == _activeSubVendorId) return;
    _activeSubVendorId = vendorId;

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
          debugPrint('[DODO][VendorSync] subscription channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] subscription channel subscribed for vendor=$vendorId');
  }

  // ── Notifications ───────────────────────────────────────────────────────────

  void resubscribeNotifications(String? vendorId) {
    if (vendorId == _activeNotifVendorId) return;
    _activeNotifVendorId = vendorId;

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

  // ── Wallet + transactions ────────────────────────────────────────────────────
  //
  // Scoped to the vendor's own wallet rows. Admin top-up, transaction creation,
  // and balance updates auto-refresh the vendor wallet screen.

  void resubscribeWallet(String? vendorId) {
    if (vendorId == _activeWalletVendorId) return;
    _activeWalletVendorId = vendorId;

    if (_walletChannel != null) {
      _client.removeChannel(_walletChannel!);
      _walletChannel = null;
    }
    if (vendorId == null) return;

    _walletChannel = _client
        .channel('dodo-vendor-wallet-$vendorId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vendor_wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'vendor_id',
            value: vendorId,
          ),
          callback: (_) {
            debugPrint('[DODO][VendorSync] vendor_wallets change → invalidating walletProvider');
            _ref.invalidate(walletProvider(vendorId));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallet_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'vendor_id',
            value: vendorId,
          ),
          callback: (_) {
            debugPrint('[DODO][VendorSync] wallet_transactions change → invalidating walletTransactionsProvider');
            _ref.invalidate(walletTransactionsProvider(vendorId));
            // Also refresh wallet summary since balance may have changed.
            _ref.invalidate(walletProvider(vendorId));
          },
        )
        .subscribe((status, error) {
          debugPrint('[DODO][VendorSync] wallet channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] wallet channel subscribed for vendor=$vendorId');
  }

  // ── Vendor documents ─────────────────────────────────────────────────────────
  //
  // Watches vendor_documents for this vendor so approval/rejection by admin
  // is reflected immediately in the vendor's documents screen.

  void resubscribeDocs(String? vendorId) {
    if (vendorId == _activeDocsVendorId) return;
    _activeDocsVendorId = vendorId;

    if (_docsChannel != null) {
      _client.removeChannel(_docsChannel!);
      _docsChannel = null;
    }
    if (vendorId == null) return;

    _docsChannel = _client
        .channel('dodo-vendor-docs-$vendorId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vendor_documents',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'vendor_id',
            value: vendorId,
          ),
          callback: (_) {
            debugPrint('[DODO][VendorSync] vendor_documents change → invalidating vendorDocumentsProvider');
            _ref.invalidate(vendorDocumentsProvider);
          },
        )
        .subscribe((status, error) {
          debugPrint('[DODO][VendorSync] docs channel status=$status error=$error');
        });
    debugPrint('[DODO][VendorSync] docs channel subscribed for vendor=$vendorId');
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  void refetchAll() {
    _invalidateBookings();
    _ref.invalidate(subscriptionSettingsProvider);
    _ref.invalidate(mySubscriptionProvider);
    _ref.invalidate(catalogServicesProvider);
    _ref.invalidate(catalogParentMapProvider);
    _ref.invalidate(vendorTrendingServicesProvider);
    _ref.invalidate(vendorDocumentsProvider);
    final vendorId = _activeWalletVendorId;
    if (vendorId != null) {
      _ref.invalidate(walletProvider(vendorId));
      _ref.invalidate(walletTransactionsProvider(vendorId));
    }
  }

  void dispose() {
    if (_bookingsChannel != null) _client.removeChannel(_bookingsChannel!);
    if (_notifChannel != null) _client.removeChannel(_notifChannel!);
    if (_subscriptionChannel != null) _client.removeChannel(_subscriptionChannel!);
    if (_settingsChannel != null) _client.removeChannel(_settingsChannel!);
    if (_walletChannel != null) _client.removeChannel(_walletChannel!);
    if (_docsChannel != null) _client.removeChannel(_docsChannel!);
    if (_catalogChannel != null) _client.removeChannel(_catalogChannel!);
  }
}

final vendorRealtimeSyncProvider = Provider<VendorRealtimeSync>((ref) {
  final sync = VendorRealtimeSync(ref, Supabase.instance.client);
  ref.onDispose(sync.dispose);

  // React to vendor user changes so per-vendor channels are created/destroyed
  // at the right time. fireImmediately:true covers the case where the vendor is
  // already authenticated when this provider first runs (hot-restart or lazy
  // initialisation after session restore). Same-value guards inside each
  // resubscribe* method prevent churn on repeated emissions.
  ref.listen<VendorUser?>(
    currentVendorUserProvider,
    (_, user) {
      sync.resubscribeNotifications(user?.id);
      sync.resubscribeSubscription(user?.id);
      sync.resubscribeWallet(user?.id);
      sync.resubscribeDocs(user?.id);
    },
    fireImmediately: true,
  );

  return sync;
});
