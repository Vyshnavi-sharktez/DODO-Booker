import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import 'notification_service.dart';
import '../models/notification_model.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

/// Resolves and caches the current customer's UUID.
/// Returns null when unauthenticated or during the initial async lookup.
/// Used by [realtimeSyncProvider] to set up the per-customer notification channel.
final currentCustomerIdProvider = FutureProvider<String?>((ref) async {
  final isAuth = ref.watch(isAuthenticatedProvider);
  if (!isAuth) return null;
  try {
    return await ref.read(notificationServiceProvider).getCustomerId();
  } catch (_) {
    return null;
  }
});

/// Manages the customer's notification list with support for in-place realtime
/// inserts so the bell/list updates immediately without a full DB re-fetch.
class NotificationsNotifier
    extends StateNotifier<AsyncValue<List<NotificationModel>>> {
  final NotificationService _service;
  final Ref _ref;

  NotificationsNotifier(this._service, this._ref)
      : super(const AsyncLoading()) {
    // React to auth changes so the list clears on logout and loads on login.
    _ref.listen<bool>(
      isAuthenticatedProvider,
      (_, isAuth) => isAuth ? _load() : _clear(),
      fireImmediately: true,
    );
  }

  Future<void> _load() async {
    state = const AsyncLoading();
    try {
      final notifications = await _service.fetchNotifications();
      if (mounted) state = AsyncData(notifications);
    } catch (e, st) {
      if (mounted) state = AsyncError(e, st);
    }
  }

  void _clear() {
    if (mounted) state = const AsyncData([]);
  }

  /// Called from [CustomerRealtimeSync] when a new notification INSERT is
  /// received via Supabase Realtime. Prepends the item immediately without a
  /// round-trip; deduplicates by ID so dual-channel events don't double-add.
  void insertFromRealtime(Map<String, dynamic> record) {
    final current = state.asData?.value;
    if (current == null) {
      // State not yet loaded — trigger a fetch instead.
      _load();
      return;
    }
    try {
      final n = NotificationModel.fromJson(record);
      if (current.any((e) => e.id == n.id)) return;
      if (mounted) state = AsyncData([n, ...current]);
    } catch (_) {
      _load();
    }
  }

  /// Full re-fetch — called after mutations (mark-read, delete, etc.)
  /// or when an UPDATE/DELETE realtime event arrives.
  Future<void> refresh() => _load();
}

/// Personal + broadcast notifications for the current customer.
/// State is updated in-place from realtime INSERTs via [NotificationsNotifier].
final notificationsProvider = StateNotifierProvider<NotificationsNotifier,
    AsyncValue<List<NotificationModel>>>(
  (ref) => NotificationsNotifier(ref.watch(notificationServiceProvider), ref),
);

/// Count of unread notifications — used for badges in header and profile.
final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).when(
        data: (list) => list.where((n) => !n.isRead).length,
        loading: () => 0,
        error: (e, _) => 0,
      );
});
