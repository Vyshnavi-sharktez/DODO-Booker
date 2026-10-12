import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/broadcast_notifications_repository.dart';
import '../../domain/models/broadcast_notification.dart';

final broadcastNotificationsRepositoryProvider =
    Provider<BroadcastNotificationsRepository>((ref) {
  return BroadcastNotificationsRepository(ref.watch(supabaseClientProvider));
});

class BroadcastNotificationsNotifier
    extends StateNotifier<AsyncValue<List<BroadcastNotification>>> {
  final BroadcastNotificationsRepository _repo;

  BroadcastNotificationsNotifier(this._repo)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchBroadcasts);
  }

  Future<void> refresh() => _load();

  Future<BroadcastNotification> createBroadcast({
    required String title,
    required String message,
    required String notificationType,
    required String audience,
    String? imageUrl,
    String? deepLink,
    required String targetingType,
    String? targetingValue,
    String? targetingLabel,
    required String status,
    DateTime? scheduledAt,
    String? createdBy,
  }) async {
    final created = await _repo.createBroadcast(
      title: title,
      message: message,
      notificationType: notificationType,
      audience: audience,
      imageUrl: imageUrl,
      deepLink: deepLink,
      targetingType: targetingType,
      targetingValue: targetingValue,
      targetingLabel: targetingLabel,
      status: status,
      scheduledAt: scheduledAt,
      createdBy: createdBy,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([created, ...current]);
    return created;
  }

  Future<int> sendBroadcast(String id) async {
    final count = await _repo.sendBroadcast(id);
    await _load();
    return count;
  }

  Future<void> deleteBroadcast(String id) async {
    await _repo.deleteBroadcast(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(current.where((b) => b.id != id).toList());
    }
  }

  // ── Realtime payload handlers ─────────────────────────────────────────────

  void applyRealtimeInsert(Map<String, dynamic> record) {
    final inserted = BroadcastNotification.fromMap(record);
    final current = state.valueOrNull;
    if (current == null) {
      _load();
      return;
    }
    if (current.any((b) => b.id == inserted.id)) return;
    state = AsyncValue.data([inserted, ...current]);
  }

  void applyRealtimeUpdate(Map<String, dynamic> record) {
    final id = record['id'] as String?;
    if (id == null) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.indexWhere((b) => b.id == id);
    if (idx == -1) {
      _load();
      return;
    }
    final updated = BroadcastNotification.fromMap(record);
    final newList = List<BroadcastNotification>.from(current);
    newList[idx] = updated;
    state = AsyncValue.data(newList);
  }

  void applyRealtimeDelete(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(current.where((b) => b.id != id).toList());
  }
}

final broadcastNotificationsNotifierProvider = StateNotifierProvider<
    BroadcastNotificationsNotifier,
    AsyncValue<List<BroadcastNotification>>>((ref) {
  return BroadcastNotificationsNotifier(
    ref.watch(broadcastNotificationsRepositoryProvider),
  );
});
