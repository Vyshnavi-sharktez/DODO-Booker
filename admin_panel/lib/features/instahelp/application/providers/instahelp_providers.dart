import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/instahelp_repository.dart';
import '../../domain/models/instahelp_mode.dart';
import '../../domain/models/instahelp_duration.dart';
import '../../domain/models/instahelp_activity.dart';
import '../../domain/models/instahelp_financial_config.dart';
import '../../domain/models/instahelp_order.dart';
import '../../domain/models/instahelp_slot_config.dart';
import '../../domain/models/instahelp_date_override.dart';

final instaHelpRepositoryProvider = Provider<InstaHelpRepository>((ref) {
  return InstaHelpRepository(ref.watch(supabaseClientProvider));
});

// ── Modes ─────────────────────────────────────────────────────────────────────

final instaHelpModesProvider =
    FutureProvider<List<InstaHelpMode>>((ref) async {
  return ref.read(instaHelpRepositoryProvider).fetchModes();
});

final instaHelpVendorModesProvider =
    FutureProvider.autoDispose.family<List<InstaHelpMode>, String>(
        (ref, vendorId) async {
  return ref.read(instaHelpRepositoryProvider).fetchVendorModes(vendorId);
});

// ── Durations notifier ────────────────────────────────────────────────────────

class InstaHelpDurationsNotifier
    extends StateNotifier<AsyncValue<List<InstaHelpDuration>>> {
  final InstaHelpRepository _repo;
  final String modeId;

  InstaHelpDurationsNotifier(this._repo, this.modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchDurations(modeId));
  }

  Future<void> refresh() => _load();

  Future<void> create({
    required String label,
    required int durationMinutes,
    required double price,
    required String discountType,
    required double discountValue,
    required bool isActive,
    required String slotStartTime,
    required String slotEndTime,
    required int slotIntervalMinutes,
    required int maxBookingsPerSlot,
  }) async {
    final current = state.valueOrNull ?? [];
    final nextOrder = current.isEmpty
        ? 0
        : current.map((d) => d.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await _repo.createDuration(
      modeId: modeId,
      label: label,
      durationMinutes: durationMinutes,
      price: price,
      discountType: discountType,
      discountValue: discountValue,
      isActive: isActive,
      sortOrder: nextOrder,
      slotStartTime: slotStartTime,
      slotEndTime: slotEndTime,
      slotIntervalMinutes: slotIntervalMinutes,
      maxBookingsPerSlot: maxBookingsPerSlot,
    );
    await _load();
  }

  Future<void> update(
    String id, {
    required String label,
    required int durationMinutes,
    required double price,
    required String discountType,
    required double discountValue,
    required bool isActive,
    required String slotStartTime,
    required String slotEndTime,
    required int slotIntervalMinutes,
    required int maxBookingsPerSlot,
  }) async {
    await _repo.updateDuration(
      id,
      label: label,
      durationMinutes: durationMinutes,
      price: price,
      discountType: discountType,
      discountValue: discountValue,
      isActive: isActive,
      slotStartTime: slotStartTime,
      slotEndTime: slotEndTime,
      slotIntervalMinutes: slotIntervalMinutes,
      maxBookingsPerSlot: maxBookingsPerSlot,
    );
    await _load();
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((d) => d.id == id ? d.copyWith(isActive: isActive) : d)
            .toList(),
      );
    }
    try {
      await _repo.toggleDurationActive(id, isActive: isActive);
    } catch (_) {
      await _load();
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _repo.deleteDuration(id);
    await _load();
  }

  Future<void> reorder(List<InstaHelpDuration> ordered) async {
    final items = <({String id, int sortOrder})>[];
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i) {
        items.add((id: ordered[i].id, sortOrder: i));
      }
    }
    if (items.isEmpty) return;
    // Optimistic update
    state = AsyncValue.data([
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(sortOrder: i),
    ]);
    try {
      await _repo.reorderDurations(items);
    } catch (_) {
      await _load();
      rethrow;
    }
  }
}

final instaHelpDurationsProvider = StateNotifierProvider.family<
    InstaHelpDurationsNotifier,
    AsyncValue<List<InstaHelpDuration>>,
    String>((ref, modeId) {
  return InstaHelpDurationsNotifier(
      ref.watch(instaHelpRepositoryProvider), modeId);
});

// ── Activities notifier ───────────────────────────────────────────────────────

class InstaHelpActivitiesNotifier
    extends StateNotifier<AsyncValue<List<InstaHelpActivity>>> {
  final InstaHelpRepository _repo;
  final String modeId;

  InstaHelpActivitiesNotifier(this._repo, this.modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchActivities(modeId));
  }

  Future<void> refresh() => _load();

  Future<void> create({
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
  }) async {
    final current = state.valueOrNull ?? [];
    final nextOrder = current.isEmpty
        ? 0
        : current.map((a) => a.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await _repo.createActivity(
      modeId,
      title: title,
      includedItems: includedItems,
      excludedItems: excludedItems,
      isActive: isActive,
      sortOrder: nextOrder,
    );
    await _load();
  }

  Future<void> update(
    String id, {
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
  }) async {
    await _repo.updateActivity(
      id,
      title: title,
      includedItems: includedItems,
      excludedItems: excludedItems,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((a) => a.id == id ? a.copyWith(isActive: isActive) : a)
            .toList(),
      );
    }
    try {
      await _repo.toggleActivityActive(id, isActive: isActive);
    } catch (_) {
      await _load();
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _repo.deleteActivity(id);
    await _load();
  }

  Future<void> reorder(List<InstaHelpActivity> ordered) async {
    final items = <({String id, int sortOrder})>[];
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i) {
        items.add((id: ordered[i].id, sortOrder: i));
      }
    }
    if (items.isEmpty) return;
    state = AsyncValue.data([
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(sortOrder: i),
    ]);
    try {
      await _repo.reorderActivities(items);
    } catch (_) {
      await _load();
      rethrow;
    }
  }
}

// Family key: modeId
final instaHelpActivitiesProvider = StateNotifierProvider.family<
    InstaHelpActivitiesNotifier,
    AsyncValue<List<InstaHelpActivity>>,
    String>((ref, modeId) {
  return InstaHelpActivitiesNotifier(
      ref.watch(instaHelpRepositoryProvider), modeId);
});

// ── Slot Config notifier ──────────────────────────────────────────────────────

class InstaHelpSlotConfigNotifier
    extends StateNotifier<AsyncValue<InstaHelpSlotConfig?>> {
  final InstaHelpRepository _repo;
  final String modeId;

  InstaHelpSlotConfigNotifier(this._repo, this.modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchSlotConfig(modeId));
  }

  Future<void> save({
    required List<int> workingDays,
    required String startTime,
    required String endTime,
    required int slotIntervalMinutes,
    required int maxBookingsPerSlot,
    required bool isActive,
  }) async {
    await _repo.upsertSlotConfig(
      modeId,
      workingDays: workingDays,
      startTime: startTime,
      endTime: endTime,
      slotIntervalMinutes: slotIntervalMinutes,
      maxBookingsPerSlot: maxBookingsPerSlot,
      isActive: isActive,
    );
    await _load();
  }
}

final instaHelpSlotConfigProvider = StateNotifierProvider.family<
    InstaHelpSlotConfigNotifier,
    AsyncValue<InstaHelpSlotConfig?>,
    String>((ref, modeId) {
  return InstaHelpSlotConfigNotifier(
      ref.watch(instaHelpRepositoryProvider), modeId);
});

// ── Date Overrides notifier ───────────────────────────────────────────────────

class InstaHelpDateOverridesNotifier
    extends StateNotifier<AsyncValue<List<InstaHelpDateOverride>>> {
  final InstaHelpRepository _repo;
  final String modeId;

  InstaHelpDateOverridesNotifier(this._repo, this.modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchDateOverrides(modeId));
  }

  Future<void> create({
    required DateTime startDate,
    required DateTime endDate,
    required bool isAvailable,
    String? customStartTime,
    String? customEndTime,
    String? notes,
  }) async {
    await _repo.createDateOverride(
      modeId,
      startDate: startDate,
      endDate: endDate,
      isAvailable: isAvailable,
      customStartTime: customStartTime,
      customEndTime: customEndTime,
      notes: notes,
    );
    await _load();
  }

  Future<void> update(
    String id, {
    required DateTime startDate,
    required DateTime endDate,
    required bool isAvailable,
    String? customStartTime,
    String? customEndTime,
    String? notes,
  }) async {
    await _repo.updateDateOverride(
      id,
      startDate: startDate,
      endDate: endDate,
      isAvailable: isAvailable,
      customStartTime: customStartTime,
      customEndTime: customEndTime,
      notes: notes,
    );
    await _load();
  }

  Future<void> delete(String id) async {
    await _repo.deleteDateOverride(id);
    await _load();
  }
}

final instaHelpDateOverridesProvider = StateNotifierProvider.family<
    InstaHelpDateOverridesNotifier,
    AsyncValue<List<InstaHelpDateOverride>>,
    String>((ref, modeId) {
  return InstaHelpDateOverridesNotifier(
      ref.watch(instaHelpRepositoryProvider), modeId);
});

// ── Financial Config notifier ─────────────────────────────────────────────────

class InstaHelpFinancialConfigNotifier
    extends StateNotifier<AsyncValue<InstaHelpFinancialConfig?>> {
  final InstaHelpRepository _repo;
  final String modeId;

  InstaHelpFinancialConfigNotifier(this._repo, this.modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchFinancialConfig(modeId));
  }

  Future<void> save({
    required double gstPercent,
    required double platformCommissionPercent,
    required bool surgeFeeEnabled,
    required String surgeFeeType,
    required double surgeFeeValue,
    required bool serviceChargeEnabled,
    required String serviceChargeType,
    required double serviceChargeValue,
  }) async {
    final saved = await _repo.upsertFinancialConfig(
      modeId,
      gstPercent: gstPercent,
      platformCommissionPercent: platformCommissionPercent,
      surgeFeeEnabled: surgeFeeEnabled,
      surgeFeeType: surgeFeeType,
      surgeFeeValue: surgeFeeValue,
      serviceChargeEnabled: serviceChargeEnabled,
      serviceChargeType: serviceChargeType,
      serviceChargeValue: serviceChargeValue,
    );
    state = AsyncValue.data(saved);
  }
}

final instaHelpFinancialConfigProvider = StateNotifierProvider.family<
    InstaHelpFinancialConfigNotifier,
    AsyncValue<InstaHelpFinancialConfig?>,
    String>((ref, modeId) {
  return InstaHelpFinancialConfigNotifier(
      ref.watch(instaHelpRepositoryProvider), modeId);
});

// ── InstaHelp Orders notifier ─────────────────────────────────────────────────

class InstaHelpOrdersNotifier
    extends StateNotifier<AsyncValue<List<InstaHelpOrder>>> {
  final InstaHelpRepository _repo;

  InstaHelpOrdersNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchInstaHelpOrders);
  }

  Future<void> refresh() async {
    if (state is! AsyncLoading) {
      try {
        final fetched = await _repo.fetchInstaHelpOrders();
        state = AsyncValue.data(fetched);
      } catch (e, st) {
        debugPrint('[InstaHelpOrders] refresh error: $e\n$st');
      }
    }
  }
}

final instaHelpOrdersNotifierProvider = StateNotifierProvider<
    InstaHelpOrdersNotifier, AsyncValue<List<InstaHelpOrder>>>((ref) {
  return InstaHelpOrdersNotifier(ref.watch(instaHelpRepositoryProvider));
});
