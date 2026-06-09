import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/services_repository.dart';
import '../../domain/models/service.dart';

final servicesRepositoryProvider = Provider<ServicesRepository>((ref) {
  return ServicesRepository(ref.watch(supabaseClientProvider));
});

class ServicesNotifier extends StateNotifier<AsyncValue<List<Service>>> {
  final ServicesRepository _repo;

  ServicesNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchServices);
  }

  Future<void> refresh() => _load();

  Future<void> createService({
    required String categoryId,
    required String subCategoryId,
    required String name,
    required String slug,
    String? description,
    required double basePrice,
    required int estimatedDuration,
    String? imageUrl,
    required bool isActive,
  }) async {
    await _repo.createService(
      categoryId: categoryId,
      subCategoryId: subCategoryId,
      name: name,
      slug: slug,
      description: description,
      basePrice: basePrice,
      estimatedDuration: estimatedDuration,
      imageUrl: imageUrl,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> updateService(
    String id, {
    required String categoryId,
    required String subCategoryId,
    required String name,
    required String slug,
    String? description,
    required double basePrice,
    required int estimatedDuration,
    String? imageUrl,
    required bool isActive,
  }) async {
    await _repo.updateService(
      id,
      categoryId: categoryId,
      subCategoryId: subCategoryId,
      name: name,
      slug: slug,
      description: description,
      basePrice: basePrice,
      estimatedDuration: estimatedDuration,
      imageUrl: imageUrl,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> deleteService(String id) async {
    await _repo.deleteService(id);
    await _load();
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((s) => s.id == id ? s.copyWith(isActive: isActive) : s)
            .toList(),
      );
    }
    try {
      await _repo.toggleActive(id, isActive: isActive);
    } catch (e) {
      await _load();
      rethrow;
    }
  }
}

final servicesNotifierProvider =
    StateNotifierProvider<ServicesNotifier, AsyncValue<List<Service>>>((ref) {
  return ServicesNotifier(ref.watch(servicesRepositoryProvider));
});
