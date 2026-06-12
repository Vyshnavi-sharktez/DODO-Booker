import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/categories_repository.dart';
import '../../domain/models/category.dart';

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) {
  return CategoriesRepository(ref.watch(supabaseClientProvider));
});

class CategoriesNotifier extends StateNotifier<AsyncValue<List<Category>>> {
  final CategoriesRepository _repo;

  CategoriesNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchCategories);
  }

  Future<void> refresh() => _load();

  Future<void> createCategory({
    required String name,
    required String slug,
    String? imageUrl,
    String? description,
    required int sortOrder,
    required bool isActive,
  }) async {
    await _repo.createCategory(
      name: name,
      slug: slug,
      imageUrl: imageUrl,
      description: description,
      sortOrder: sortOrder,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> updateCategory(
    String id, {
    required String name,
    required String slug,
    String? imageUrl,
    String? description,
    required int sortOrder,
    required bool isActive,
  }) async {
    await _repo.updateCategory(
      id,
      name: name,
      slug: slug,
      imageUrl: imageUrl,
      description: description,
      sortOrder: sortOrder,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> deleteCategory(String id) async {
    await _repo.deleteCategory(id);
    await _load();
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    // Optimistic update
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((c) => c.id == id ? c.copyWith(isActive: isActive) : c)
            .toList(),
      );
    }
    try {
      await _repo.toggleActive(id, isActive: isActive);
    } catch (e) {
      // Revert on failure
      await _load();
      rethrow;
    }
  }
}

final categoriesNotifierProvider =
    StateNotifierProvider<CategoriesNotifier, AsyncValue<List<Category>>>((ref) {
  return CategoriesNotifier(ref.watch(categoriesRepositoryProvider));
});
