import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/service_addons_repository.dart';
import '../../domain/models/service_addon.dart';

final serviceAddonsRepositoryProvider =
    Provider<ServiceAddonsRepository>((ref) {
  return ServiceAddonsRepository(ref.watch(supabaseClientProvider));
});

class ServiceAddonsNotifier
    extends StateNotifier<AsyncValue<List<ServiceAddon>>> {
  final ServiceAddonsRepository _repo;
  String? _currentServiceId;

  ServiceAddonsNotifier(this._repo) : super(const AsyncValue.data([]));

  Future<void> loadForService(String serviceId) async {
    _currentServiceId = serviceId;
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> _reload() async {
    if (_currentServiceId == null) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.fetchByService(_currentServiceId!),
    );
  }

  Future<void> create({
    required String serviceId,
    required String name,
    String? description,
    required double price,
    required bool isActive,
  }) async {
    await _repo.create(
      serviceId: serviceId,
      name: name,
      description: description,
      price: price,
      isActive: isActive,
    );
    await _reload();
  }

  Future<void> update(
    String id, {
    required String name,
    String? description,
    required double price,
    required bool isActive,
  }) async {
    await _repo.update(
      id,
      name: name,
      description: description,
      price: price,
      isActive: isActive,
    );
    await _reload();
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    // Optimistic update
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
      await _reload(); // revert on failure
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await _reload();
  }
}

final serviceAddonsNotifierProvider = StateNotifierProvider<
    ServiceAddonsNotifier, AsyncValue<List<ServiceAddon>>>((ref) {
  return ServiceAddonsNotifier(ref.watch(serviceAddonsRepositoryProvider));
});

/// Read-only per-service provider used by the catalog tile to display inline
/// add-on chips. Separate from [serviceAddonsNotifierProvider] so multiple
/// tiles can display add-ons simultaneously without interfering with the
/// single-service CRUD dialog state.
final serviceAddonsByServiceIdProvider =
    FutureProvider.family<List<ServiceAddon>, String>(
  (ref, serviceId) =>
      ref.read(serviceAddonsRepositoryProvider).fetchByService(serviceId),
);
