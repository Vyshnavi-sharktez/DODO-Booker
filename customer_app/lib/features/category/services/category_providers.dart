import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'category_service.dart';
import '../../../models/category_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/service_model.dart';
import '../../../models/subcategory_model.dart';

final categoryServiceProvider = Provider<CategoryService>(
  (ref) => CategoryService(),
);

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) {
  return ref.read(categoryServiceProvider).fetchCategories();
});

final subcategoriesProvider =
    FutureProvider.family<List<SubcategoryModel>, String>(
  (ref, categoryId) {
    debugPrint('[DODO][Provider] subcategoriesProvider(categoryId=$categoryId)');
    return ref
        .read(categoryServiceProvider)
        .fetchSubcategoriesByCategoryId(categoryId);
  },
);

final servicesBySubcategoryProvider =
    FutureProvider.family<List<ServiceModel>, String>(
  (ref, subcategoryId) {
    debugPrint(
        '[DODO][Provider] servicesBySubcategoryProvider(subcategoryId=$subcategoryId)');
    return ref
        .read(categoryServiceProvider)
        .fetchServicesBySubcategoryId(subcategoryId);
  },
);

final serviceAttributesProvider =
    FutureProvider.family<List<ServiceAttributeModel>, String>(
  (ref, serviceId) {
    debugPrint(
        '[DODO][Provider] serviceAttributesProvider(serviceId=$serviceId)');
    return ref
        .read(categoryServiceProvider)
        .fetchServiceAttributes(serviceId);
  },
);

/// Resolves a subcategory → primary service → service attributes in one shot.
/// Calls the service directly (not via chained providers) so errors are never
/// served from a stale cached provider state.
final subcategoryDetailsProvider =
    FutureProvider.family<SubcategoryDetails, String>(
  (ref, subcategoryId) async {
    final svc = ref.read(categoryServiceProvider);

    debugPrint(
        '[DODO][Provider] subcategoryDetailsProvider START subcategoryId=$subcategoryId');

    final services = await svc.fetchServicesBySubcategoryId(subcategoryId);
    debugPrint(
        '[DODO][Provider] subcategoryDetailsProvider → services=${services.length}');

    if (services.isEmpty) {
      debugPrint(
          '[DODO][Provider] subcategoryDetailsProvider → no service found for subcategoryId=$subcategoryId');
      return const SubcategoryDetails(service: null, attributes: []);
    }

    final service = services.first;
    debugPrint(
        '[DODO][Provider] subcategoryDetailsProvider → primary service id=${service.id} name=${service.name}');

    final attributes = await svc.fetchServiceAttributes(service.id);
    debugPrint(
        '[DODO][Provider] subcategoryDetailsProvider → attributes=${attributes.length}');

    return SubcategoryDetails(service: service, attributes: attributes);
  },
);

class SubcategoryDetails {
  final ServiceModel? service;
  final List<ServiceAttributeModel> attributes;

  const SubcategoryDetails({
    required this.service,
    required this.attributes,
  });

  bool get hasService => service != null;
  bool get hasAttributes => attributes.isNotEmpty;
}
