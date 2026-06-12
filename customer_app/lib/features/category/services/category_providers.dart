import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'category_service.dart';
import '../../../models/category_model.dart';
import '../../../models/subcategory_model.dart';

final categoryServiceProvider = Provider<CategoryService>(
  (ref) => CategoryService(),
);

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) {
  return ref.read(categoryServiceProvider).fetchCategories();
});

final subcategoriesProvider =
    FutureProvider.family<List<SubcategoryModel>, String>(
  (ref, categoryId) => ref
      .read(categoryServiceProvider)
      .fetchSubcategoriesByCategoryId(categoryId),
);
