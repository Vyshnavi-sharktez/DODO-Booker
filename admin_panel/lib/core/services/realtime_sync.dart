import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/application/providers/auth_provider.dart';
import '../../features/bookings/application/providers/bookings_providers.dart';
import '../../features/bookings/application/providers/dispatch_providers.dart';
import '../../features/customer_questions/application/providers/customer_questions_providers.dart';
import '../../features/customers/application/providers/customers_providers.dart';
import '../../features/notifications/application/providers/notifications_providers.dart';
import '../../features/refunds/application/refund_providers.dart';
import '../../features/support/application/support_providers.dart';
import '../../features/vendor_settlement/application/providers/vendor_settlement_providers.dart';
import '../../features/vendors/application/providers/vendors_providers.dart';
import '../../features/warranties/application/warranties_providers.dart';

/// Manages Supabase Realtime subscriptions for the admin panel.
///
/// Kept alive for the lifetime of the ProviderScope via [adminRealtimeSyncProvider].
///
/// All subscriptions share a single `dodo-admin-sync` channel to minimise
/// connection overhead. Events that need per-record granularity (refund messages,
/// open support thread) use the currently-selected record ID stored in state.
///
/// Event → action map:
///   bookings              → bookingsNotifierProvider.refresh()
///   customer_reviews      → bookingsNotifierProvider.refresh()
///   vendors UPDATE        → vendorsNotifierProvider.refresh()
///   notifications INSERT  → applyRealtimeInsert (payload, no DB fetch)
///   notifications UPDATE  → applyRealtimeUpdate (payload, no DB fetch)
///   notifications DELETE  → applyRealtimeDelete (payload, no DB fetch)
///   customer_questions    → customerQuestionsNotifierProvider.invalidate()
///   support_conversations → supportConversationsProvider + open detail
///   support_messages      → supportMessagesProvider(selectedId)
///   refund_requests       → refundRequestsProvider + open detail
///   refund_status_history → refundRequestsProvider + open detail
///   refund_messages       → refundAdminMessagesProvider(openId)
///   vendor_settlements /
///   vendor_settlement_bookings → vendorSettlementNotifierProvider.refresh()
///                                + per-vendor FutureProviders
///   service_warranties    → adminWarrantiesProvider
///   customers             → customersNotifierProvider.refresh()
class AdminRealtimeSync {
  final Ref _ref;
  final SupabaseClient _client;
  RealtimeChannel? _channel;

  AdminRealtimeSync(this._ref, this._client) {
    _subscribe();
    // Dispatch escalation processing is kept as a timer because it triggers
    // a server-side RPC (processPendingDispatchEscalations). The UI update
    // on escalation is already covered by the bookings realtime subscription
    // above — when an escalation level changes the bookings UPDATE event fires.
    _ref.watch(dispatchEscalationTimerProvider);
  }

  void _subscribe() {
    _channel = _client
        .channel('dodo-admin-sync')
        // ── Bookings ─────────────────────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (_) => _refreshBookings(),
        )
        // ── Customer reviews ──────────────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'customer_reviews',
          callback: (_) => _refreshBookings(),
        )
        // ── Vendor status changes (online/offline toggle) ─────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'vendors',
          callback: (_) => _refreshVendors(),
        )
        // ── Admin notifications ───────────────────────────────────────────────
        // Each event type is handled from the payload to avoid a full DB
        // reload. A full reload races against in-flight is_read UPDATEs and
        // can fetch stale is_read=false, making a just-read notification
        // appear unread again.
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (p) {
            final record = p.newRecord;
            if (record.isNotEmpty) {
              _ref
                  .read(notificationsNotifierProvider.notifier)
                  .applyRealtimeInsert(record);
            } else {
              _refreshNotifications();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          callback: (p) {
            final record = p.newRecord;
            if (record.isNotEmpty) {
              _ref
                  .read(notificationsNotifierProvider.notifier)
                  .applyRealtimeUpdate(record);
            } else {
              _refreshNotifications();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'notifications',
          callback: (p) {
            final id = p.oldRecord['id'] as String?;
            if (id != null) {
              _ref
                  .read(notificationsNotifierProvider.notifier)
                  .applyRealtimeDelete(id);
            } else {
              _refreshNotifications();
            }
          },
        )
        // ── Customer questions ────────────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'customer_questions',
          callback: (_) => _refreshCustomerQuestions(),
        )
        // ── Support conversations ─────────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'support_conversations',
          callback: (_) => _refreshSupportConversations(),
        )
        // ── Support messages ──────────────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_messages',
          callback: (_) => _refreshSupportMessages(),
        )
        // ── Refund requests (new ticket or status change) ─────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'refund_requests',
          callback: (_) => _refreshRefunds(),
        )
        // ── Refund status history (timeline events) ───────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'refund_status_history',
          callback: (_) => _refreshRefunds(),
        )
        // ── Refund messages (new customer or admin message) ───────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'refund_messages',
          callback: (_) => _refreshRefundMessages(),
        )
        // ── Vendor settlements (new batch or status update) ───────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vendor_settlements',
          callback: (_) => _refreshSettlements(),
        )
        // ── Settlement booking rows ───────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vendor_settlement_bookings',
          callback: (_) => _refreshSettlements(),
        )
        // ── Warranty claims (new claim or status change) ──────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_warranties',
          callback: (_) => _refreshWarranties(),
        )
        // ── Customer profile changes ──────────────────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'customers',
          callback: (_) => _refreshCustomers(),
        )
        .subscribe((status, error) {
          debugPrint('[DODO][AdminSync] channel status=$status error=$error');
        });
  }

  // ── Refresh helpers ───────────────────────────────────────────────────────────

  void _refreshBookings() {
    debugPrint('[DODO][AdminSync] bookings event → refresh');
    _ref.read(bookingsNotifierProvider.notifier).refresh();
  }

  void _refreshVendors() {
    debugPrint('[DODO][AdminSync] vendors event → refresh');
    _ref.read(vendorsNotifierProvider.notifier).refresh();
  }

  void _refreshNotifications() {
    debugPrint('[DODO][AdminSync] notifications event → refresh');
    _ref.read(notificationsNotifierProvider.notifier).refresh();
  }

  void _refreshCustomerQuestions() {
    debugPrint('[DODO][AdminSync] customer_questions INSERT → invalidate');
    _ref.invalidate(customerQuestionsNotifierProvider);
  }

  void _refreshSupportConversations() {
    debugPrint('[DODO][AdminSync] support_conversations event → invalidate');
    _ref.invalidate(supportConversationsProvider);
    final selectedId = _ref.read(selectedSupportConversationIdProvider);
    if (selectedId != null) {
      _ref.invalidate(supportConversationDetailProvider(selectedId));
    }
  }

  void _refreshSupportMessages() {
    debugPrint('[DODO][AdminSync] support_messages INSERT → invalidate');
    final selectedId = _ref.read(selectedSupportConversationIdProvider);
    if (selectedId != null) {
      _ref.invalidate(supportMessagesProvider(selectedId));
    }
    _ref.invalidate(supportConversationsProvider);
  }

  void _refreshRefunds() {
    debugPrint('[DODO][AdminSync] refund event → invalidating refund providers');
    _ref.invalidate(refundRequestsProvider);
    // Also invalidate the open ticket detail if one is visible.
    final openId = _ref.read(selectedRefundRequestIdProvider);
    if (openId != null) {
      _ref.invalidate(refundRequestDetailProvider(openId));
    }
  }

  void _refreshRefundMessages() {
    debugPrint('[DODO][AdminSync] refund_messages INSERT → invalidating message provider');
    final openId = _ref.read(selectedRefundRequestIdProvider);
    if (openId != null) {
      // Do NOT invalidate refundRequestDetailProvider here — only messages
      // changed. Invalidating the full detail would cause the dialog to
      // flash a loading spinner on every new message.
      _ref.invalidate(refundAdminMessagesProvider(openId));
    }
    // Always refresh the list so unread counts / last-message preview update.
    _ref.invalidate(refundRequestsProvider);
  }

  void _refreshSettlements() {
    debugPrint('[DODO][AdminSync] settlement event → refresh');
    _ref.read(vendorSettlementNotifierProvider.notifier).refresh();
    // Invalidate per-vendor FutureProviders so open vendor details pages update.
    _ref.invalidate(vendorBookingRowsProvider);
    _ref.invalidate(vendorPendingSettlementProvider);
    _ref.invalidate(settlementHistoryProvider);
    _ref.invalidate(vendorSettlementHistoryProvider);
    _ref.invalidate(thisMonthSettlementStatsProvider);
  }

  void _refreshWarranties() {
    debugPrint('[DODO][AdminSync] service_warranties event → invalidating warranty providers');
    _ref.invalidate(adminWarrantiesProvider);
    _ref.invalidate(adminAnalyticsWarrantiesProvider);
  }

  void _refreshCustomers() {
    debugPrint('[DODO][AdminSync] customers UPDATE → refresh');
    _ref.read(customersNotifierProvider.notifier).refresh();
  }

  /// Called by the lifecycle observer on admin panel resume after a long pause.
  void refetchAll() {
    _refreshBookings();
    _refreshVendors();
    _refreshNotifications();
    _ref.invalidate(refundRequestsProvider);
    _ref.read(vendorSettlementNotifierProvider.notifier).refresh();
    _ref.invalidate(adminWarrantiesProvider);
    _ref.read(customersNotifierProvider.notifier).refresh();
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
