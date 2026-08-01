import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/amc_plans_repository.dart';
import '../../domain/models/amc_plan.dart';

final amcPlansRepositoryProvider = Provider<AmcPlansRepository>((ref) {
  return AmcPlansRepository(ref.watch(supabaseClientProvider));
});

// ── All-plans notifier (AMC Plans page) ───────────────────────────────────────

class AllAmcPlansNotifier
    extends StateNotifier<AsyncValue<List<AmcPlan>>> {
  final AmcPlansRepository _repo;

  AllAmcPlansNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> refresh() => _load();

  Future<void> create({
    required String planName,
    required String packageDuration,
    int? packageDurationValue,
    required String serviceInterval,
    int? serviceIntervalValue,
    required double pricePerVisit,
    required String discountType,
    required double discountValue,
    required bool isActive,
  }) async {
    await _repo.create(
      planName: planName,
      packageDuration: packageDuration,
      packageDurationValue: packageDurationValue,
      serviceInterval: serviceInterval,
      serviceIntervalValue: serviceIntervalValue,
      pricePerVisit: pricePerVisit,
      discountType: discountType,
      discountValue: discountValue,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> update(
    String id, {
    required String planName,
    required String packageDuration,
    int? packageDurationValue,
    required String serviceInterval,
    int? serviceIntervalValue,
    required double pricePerVisit,
    required String discountType,
    required double discountValue,
    required bool isActive,
  }) async {
    await _repo.update(
      id,
      planName: planName,
      packageDuration: packageDuration,
      packageDurationValue: packageDurationValue,
      serviceInterval: serviceInterval,
      serviceIntervalValue: serviceIntervalValue,
      pricePerVisit: pricePerVisit,
      discountType: discountType,
      discountValue: discountValue,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((p) => p.id == id ? p.copyWith(isActive: isActive) : p)
            .toList(),
      );
    }
    try {
      await _repo.toggleActive(id, isActive: isActive);
    } catch (_) {
      await _load();
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await _load();
  }
}

final allAmcPlansNotifierProvider = StateNotifierProvider<AllAmcPlansNotifier,
    AsyncValue<List<AmcPlan>>>((ref) {
  return AllAmcPlansNotifier(ref.watch(amcPlansRepositoryProvider));
});

// ── Node-plans notifier (per catalog node) ─────────────────────────────────────

class NodeAmcPlansNotifier extends StateNotifier<AsyncValue<List<String>>> {
  final AmcPlansRepository _repo;
  final String _nodeId;

  NodeAmcPlansNotifier(this._repo, this._nodeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchLinkedPlanIds(_nodeId));
  }

  Future<void> sync(List<String> planIds) async {
    await _repo.syncNodePlans(_nodeId, planIds);
    await _load();
  }
}

final nodeAmcPlansNotifierProvider = StateNotifierProvider.autoDispose
    .family<NodeAmcPlansNotifier, AsyncValue<List<String>>, String>(
  (ref, nodeId) =>
      NodeAmcPlansNotifier(ref.watch(amcPlansRepositoryProvider), nodeId),
);
