import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/sub_categories_repository.dart';
import '../../domain/models/sub_category.dart';

final subCategoriesRepositoryProvider =
    Provider<SubCategoriesRepository>((ref) {
  return SubCategoriesRepository(ref.watch(supabaseClientProvider));
});

class SubCategoriesNotifier
    extends StateNotifier<AsyncValue<List<SubCategory>>> {
  final SubCategoriesRepository _repo;

  SubCategoriesNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchSubCategories);
  }

  Future<void> refresh() => _load();

  Future<void> createSubCategory({
    required String categoryId,
    required String name,
    required String slug,
    String? description,
    required int sortOrder,
    required bool isActive,
  }) async {
    await _repo.createSubCategory(
      categoryId: categoryId,
      name: name,
      slug: slug,
      description: description,
      sortOrder: sortOrder,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> updateSubCategory(
    String id, {
    required String categoryId,
    required String name,
    required String slug,
    String? description,
    required int sortOrder,
    required bool isActive,
  }) async {
    await _repo.updateSubCategory(
      id,
      categoryId: categoryId,
      name: name,
      slug: slug,
      description: description,
      sortOrder: sortOrder,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> deleteSubCategory(String id) async {
    await _repo.deleteSubCategory(id);
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

final subCategoriesNotifierProvider = StateNotifierProvider<
    SubCategoriesNotifier, AsyncValue<List<SubCategory>>>((ref) {
  return SubCategoriesNotifier(ref.watch(subCategoriesRepositoryProvider));
});
