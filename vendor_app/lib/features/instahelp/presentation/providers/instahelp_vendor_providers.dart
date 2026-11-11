import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/instahelp_vendor_repository.dart';
import '../../domain/models/instahelp_mode.dart';
import '../../domain/models/instahelp_duration.dart';
import '../../domain/models/instahelp_activity.dart';
import '../../domain/models/instahelp_slot_config.dart';
import '../../domain/models/instahelp_financial_config.dart';
import '../../domain/models/instahelp_date_override.dart';

final instaHelpVendorRepoProvider = Provider<InstaHelpVendorRepository>((ref) {
  return InstaHelpVendorRepository(ref.watch(supabaseClientProvider));
});

// ── Modes ─────────────────────────────────────────────────────────────────────

class VendorModesNotifier extends StateNotifier<AsyncValue<List<InstaHelpMode>>> {
  final InstaHelpVendorRepository _repo;
  final String _vendorId;

  VendorModesNotifier(this._repo, this._vendorId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchVendorModes(_vendorId));
  }

  Future<void> initialize() async {
    await _repo.initializeVendorModes(_vendorId);
    await _load();
  }

  Future<void> toggleActive(String modeId, {required bool isActive}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((m) => m.id == modeId
            ? InstaHelpMode(id: m.id, modeType: m.modeType, isActive: isActive, vendorId: m.vendorId)
            : m).toList(),
      );
    }
    try {
      await _repo.toggleModeActive(modeId, isActive: isActive);
    } catch (_) {
      await _load();
      rethrow;
    }
  }
}

final vendorModesProvider = StateNotifierProvider.family<
    VendorModesNotifier, AsyncValue<List<InstaHelpMode>>, String>(
  (ref, vendorId) => VendorModesNotifier(ref.watch(instaHelpVendorRepoProvider), vendorId),
);

// ── Durations ─────────────────────────────────────────────────────────────────

class VendorDurationsNotifier
    extends StateNotifier<AsyncValue<List<InstaHelpDuration>>> {
  final InstaHelpVendorRepository _repo;
  final String _modeId;

  VendorDurationsNotifier(this._repo, this._modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchDurations(_modeId));
  }

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
      modeId: _modeId,
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

  Future<void> update(String id, {
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
    await _repo.updateDuration(id,
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
        current.map((d) => d.id == id ? d.copyWith(isActive: isActive) : d).toList(),
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
      if (ordered[i].sortOrder != i) items.add((id: ordered[i].id, sortOrder: i));
    }
    if (items.isEmpty) return;
    state = AsyncValue.data([
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(sortOrder: i),
    ]);
    try {
      await _repo.reorderDurations(items);
    } catch (_) {
      await _load();
      rethrow;
    }
  }
}

final vendorDurationsProvider = StateNotifierProvider.family<
    VendorDurationsNotifier, AsyncValue<List<InstaHelpDuration>>, String>(
  (ref, modeId) => VendorDurationsNotifier(ref.watch(instaHelpVendorRepoProvider), modeId),
);

// ── Activities ─────────────────────────────────────────────────────────────────

class VendorActivitiesNotifier
    extends StateNotifier<AsyncValue<List<InstaHelpActivity>>> {
  final InstaHelpVendorRepository _repo;
  final String _modeId;

  VendorActivitiesNotifier(this._repo, this._modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchActivities(_modeId));
  }

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
    await _repo.createActivity(_modeId,
      title: title,
      includedItems: includedItems,
      excludedItems: excludedItems,
      isActive: isActive,
      sortOrder: nextOrder,
    );
    await _load();
  }

  Future<void> update(String id, {
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
  }) async {
    await _repo.updateActivity(id,
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
        current.map((a) => a.id == id ? a.copyWith(isActive: isActive) : a).toList(),
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
      if (ordered[i].sortOrder != i) items.add((id: ordered[i].id, sortOrder: i));
    }
    if (items.isEmpty) return;
    state = AsyncValue.data([
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(sortOrder: i),
    ]);
    try {
      await _repo.reorderActivities(items);
    } catch (_) {
      await _load();
      rethrow;
    }
  }
}

final vendorActivitiesProvider = StateNotifierProvider.family<
    VendorActivitiesNotifier, AsyncValue<List<InstaHelpActivity>>, String>(
  (ref, modeId) => VendorActivitiesNotifier(ref.watch(instaHelpVendorRepoProvider), modeId),
);

// ── Slot Config ────────────────────────────────────────────────────────────────

class VendorSlotConfigNotifier
    extends StateNotifier<AsyncValue<InstaHelpSlotConfig?>> {
  final InstaHelpVendorRepository _repo;
  final String _modeId;

  VendorSlotConfigNotifier(this._repo, this._modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchSlotConfig(_modeId));
  }

  Future<void> save({
    required List<int> workingDays,
    required String startTime,
    required String endTime,
    required int slotIntervalMinutes,
    required int maxBookingsPerSlot,
    required bool isActive,
  }) async {
    await _repo.upsertSlotConfig(_modeId,
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

final vendorSlotConfigProvider = StateNotifierProvider.family<
    VendorSlotConfigNotifier, AsyncValue<InstaHelpSlotConfig?>, String>(
  (ref, modeId) => VendorSlotConfigNotifier(ref.watch(instaHelpVendorRepoProvider), modeId),
);

// ── Financial Config ───────────────────────────────────────────────────────────

class VendorFinancialConfigNotifier
    extends StateNotifier<AsyncValue<InstaHelpFinancialConfig?>> {
  final InstaHelpVendorRepository _repo;
  final String _modeId;

  VendorFinancialConfigNotifier(this._repo, this._modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchFinancialConfig(_modeId));
  }

  Future<void> save({
    required double gstPercent,
    required bool surgeFeeEnabled,
    required String surgeFeeType,
    required double surgeFeeValue,
    required bool serviceChargeEnabled,
    required String serviceChargeType,
    required double serviceChargeValue,
  }) async {
    await _repo.upsertFinancialConfig(_modeId,
      gstPercent: gstPercent,
      surgeFeeEnabled: surgeFeeEnabled,
      surgeFeeType: surgeFeeType,
      surgeFeeValue: surgeFeeValue,
      serviceChargeEnabled: serviceChargeEnabled,
      serviceChargeType: serviceChargeType,
      serviceChargeValue: serviceChargeValue,
    );
    await _load();
  }
}

final vendorFinancialConfigProvider = StateNotifierProvider.family<
    VendorFinancialConfigNotifier, AsyncValue<InstaHelpFinancialConfig?>, String>(
  (ref, modeId) => VendorFinancialConfigNotifier(ref.watch(instaHelpVendorRepoProvider), modeId),
);

final vendorInstaHelpEligibilityProvider = FutureProvider.family<bool, String>(
  (ref, vendorId) => ref.watch(instaHelpVendorRepoProvider).checkEligibility(vendorId),
);

// ── Date Overrides ─────────────────────────────────────────────────────────────

class VendorDateOverridesNotifier
    extends StateNotifier<AsyncValue<List<InstaHelpDateOverride>>> {
  final InstaHelpVendorRepository _repo;
  final String _modeId;

  VendorDateOverridesNotifier(this._repo, this._modeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchDateOverrides(_modeId));
  }

  Future<void> create({
    required DateTime startDate,
    required DateTime endDate,
    required bool isAvailable,
    required String? customStartTime,
    required String? customEndTime,
    required String? notes,
  }) async {
    await _repo.createDateOverride(
      _modeId,
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
    required String? customStartTime,
    required String? customEndTime,
    required String? notes,
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

final vendorDateOverridesProvider = StateNotifierProvider.family<
    VendorDateOverridesNotifier, AsyncValue<List<InstaHelpDateOverride>>, String>(
  (ref, modeId) =>
      VendorDateOverridesNotifier(ref.watch(instaHelpVendorRepoProvider), modeId),
);
