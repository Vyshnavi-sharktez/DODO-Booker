import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/service_addons_repository.dart';
import '../../domain/models/service_addon.dart';

final serviceAddonsRepositoryProvider =
    Provider<ServiceAddonsRepository>((ref) {
  return ServiceAddonsRepository(ref.watch(supabaseClientProvider));
});

// ── Global add-ons notifier (standalone Add-ons page) ────────────────────────

class AllAddonsNotifier extends StateNotifier<AsyncValue<List<ServiceAddon>>> {
  final ServiceAddonsRepository _repo;

  AllAddonsNotifier(this._repo) : super(const AsyncValue.data([])) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> refresh() => _load();

  Future<void> create({
    required String name,
    String? description,
    required double price,
    required bool isActive,
    String? serviceId,
  }) async {
    await _repo.create(
      name: name,
      description: description,
      price: price,
      isActive: isActive,
      serviceId: serviceId,
    );
    await _load();
  }

  Future<void> update(
    String id, {
    required String name,
    String? description,
    required double price,
    required bool isActive,
    String? serviceId,
  }) async {
    await _repo.update(
      id,
      name: name,
      description: description,
      price: price,
      isActive: isActive,
      serviceId: serviceId,
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

final allAddonsNotifierProvider = StateNotifierProvider<AllAddonsNotifier,
    AsyncValue<List<ServiceAddon>>>((ref) {
  return AllAddonsNotifier(ref.watch(serviceAddonsRepositoryProvider));
});
