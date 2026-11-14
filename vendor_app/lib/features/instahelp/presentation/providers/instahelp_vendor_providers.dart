import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

// ── Realtime requests (pending + rejected) for a mode ────────────────────────

class VendorInstaHelpRequestsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final InstaHelpVendorRepository _repo;
  final SupabaseClient _supabase;
  final String _modeId;
  RealtimeChannel? _channel;
  int _gen = 0;

  VendorInstaHelpRequestsNotifier(this._repo, this._supabase, this._modeId)
      : super(const AsyncValue.loading()) {
    _load();
    _subscribe();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    if (!state.hasValue) state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => _repo.fetchModeRequests(_modeId));
    if (_gen == gen && mounted) state = result;
  }

  void _subscribe() {
    _channel = _supabase
        .channel('vendor-ih-requests-$_modeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vendor_service_requests',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }
}

final vendorInstaHelpRequestsProvider = StateNotifierProvider.autoDispose.family<
    VendorInstaHelpRequestsNotifier,
    AsyncValue<List<Map<String, dynamic>>>,
    String>(
  (ref, modeId) => VendorInstaHelpRequestsNotifier(
    ref.watch(instaHelpVendorRepoProvider),
    ref.watch(supabaseClientProvider),
    modeId,
  ),
);

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
            ? m.copyWith(isActive: isActive)
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

  Future<void> reorder(List<InstaHelpMode> ordered) async {
    final items = <({String id, int sortOrder})>[];
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i) items.add((id: ordered[i].id, sortOrder: i));
    }
    if (items.isEmpty) return;
    state = AsyncValue.data([
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(sortOrder: i),
    ]);
    try {
      await _repo.reorderModes(items);
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
  final Ref _ref;
  final SupabaseClient _supabase;
  RealtimeChannel? _channel;
  int _gen = 0;

  VendorDurationsNotifier(this._repo, this._modeId, this._ref, this._supabase)
      : super(const AsyncValue.loading()) {
    _load();
    _subscribe();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    if (!state.hasValue) state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => _repo.fetchDurations(_modeId));
    if (_gen == gen && mounted) state = result;
  }

  void _subscribe() {
    _channel = _supabase
        .channel('vendor-ih-durations-$_modeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'instahelp_durations',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  void _invalidatePending() {
    if (mounted) _ref.invalidate(vendorInstaHelpRequestsProvider(_modeId));
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
    _invalidatePending();
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
    _invalidatePending();
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _repo.toggleDurationActive(id, isActive: isActive);
    _invalidatePending();
  }

  Future<void> delete(String id) async {
    await _repo.deleteDuration(id);
    _invalidatePending();
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
  (ref, modeId) => VendorDurationsNotifier(
    ref.watch(instaHelpVendorRepoProvider), modeId, ref, ref.watch(supabaseClientProvider)),
);

// ── Activities ─────────────────────────────────────────────────────────────────

class VendorActivitiesNotifier
    extends StateNotifier<AsyncValue<List<InstaHelpActivity>>> {
  final InstaHelpVendorRepository _repo;
  final String _modeId;
  final Ref _ref;
  final SupabaseClient _supabase;
  RealtimeChannel? _channel;
  int _gen = 0;

  VendorActivitiesNotifier(this._repo, this._modeId, this._ref, this._supabase)
      : super(const AsyncValue.loading()) {
    _load();
    _subscribe();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    if (!state.hasValue) state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => _repo.fetchActivities(_modeId));
    if (_gen == gen && mounted) state = result;
  }

  void _subscribe() {
    _channel = _supabase
        .channel('vendor-ih-activities-$_modeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'instahelp_activities',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  void _invalidatePending() {
    if (mounted) _ref.invalidate(vendorInstaHelpRequestsProvider(_modeId));
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
    _invalidatePending();
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
    _invalidatePending();
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _repo.toggleActivityActive(id, isActive: isActive);
    _invalidatePending();
  }

  Future<void> delete(String id) async {
    await _repo.deleteActivity(id);
    _invalidatePending();
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
  (ref, modeId) => VendorActivitiesNotifier(
    ref.watch(instaHelpVendorRepoProvider), modeId, ref, ref.watch(supabaseClientProvider)),
);

// ── Slot Config ────────────────────────────────────────────────────────────────

class VendorSlotConfigNotifier
    extends StateNotifier<AsyncValue<InstaHelpSlotConfig?>> {
  final InstaHelpVendorRepository _repo;
  final String _modeId;
  final Ref _ref;
  final SupabaseClient _supabase;
  RealtimeChannel? _channel;
  int _gen = 0;

  VendorSlotConfigNotifier(this._repo, this._modeId, this._ref, this._supabase)
      : super(const AsyncValue.loading()) {
    _load();
    _subscribe();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    if (!state.hasValue) state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => _repo.fetchSlotConfig(_modeId));
    if (_gen == gen && mounted) state = result;
  }

  void _subscribe() {
    _channel = _supabase
        .channel('vendor-ih-slotconfig-$_modeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'instahelp_slot_config',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
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
    if (mounted) _ref.invalidate(vendorInstaHelpRequestsProvider(_modeId));
  }

  Future<void> delete() async {
    await _repo.deleteSlotConfig(_modeId);
    if (mounted) _ref.invalidate(vendorInstaHelpRequestsProvider(_modeId));
  }
}

final vendorSlotConfigProvider = StateNotifierProvider.family<
    VendorSlotConfigNotifier, AsyncValue<InstaHelpSlotConfig?>, String>(
  (ref, modeId) => VendorSlotConfigNotifier(
    ref.watch(instaHelpVendorRepoProvider), modeId, ref, ref.watch(supabaseClientProvider)),
);

// ── Financial Config ───────────────────────────────────────────────────────────

class VendorFinancialConfigNotifier
    extends StateNotifier<AsyncValue<InstaHelpFinancialConfig?>> {
  final InstaHelpVendorRepository _repo;
  final String _modeId;
  final Ref _ref;
  final SupabaseClient _supabase;
  RealtimeChannel? _channel;
  int _gen = 0;

  VendorFinancialConfigNotifier(this._repo, this._modeId, this._ref, this._supabase)
      : super(const AsyncValue.loading()) {
    _load();
    _subscribe();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    if (!state.hasValue) state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => _repo.fetchFinancialConfig(_modeId));
    if (_gen == gen && mounted) state = result;
  }

  void _subscribe() {
    _channel = _supabase
        .channel('vendor-ih-financialconfig-$_modeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'instahelp_financial_config',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
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
    if (mounted) _ref.invalidate(vendorInstaHelpRequestsProvider(_modeId));
  }
}

final vendorFinancialConfigProvider = StateNotifierProvider.family<
    VendorFinancialConfigNotifier, AsyncValue<InstaHelpFinancialConfig?>, String>(
  (ref, modeId) => VendorFinancialConfigNotifier(
    ref.watch(instaHelpVendorRepoProvider), modeId, ref, ref.watch(supabaseClientProvider)),
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
