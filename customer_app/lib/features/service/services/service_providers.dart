import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'service_service.dart';
import '../../../models/service_model.dart';

final serviceServiceProvider = Provider<ServiceService>(
  (ref) => ServiceService(),
);

final servicesBySubcategoryProvider =
    FutureProvider.family<List<ServiceModel>, String>(
  (ref, subcategoryId) => ref
      .read(serviceServiceProvider)
      .fetchServicesBySubcategoryId(subcategoryId),
);

final serviceDetailProvider =
    FutureProvider.family<ServiceModel?, String>(
  (ref, serviceId) =>
      ref.read(serviceServiceProvider).fetchServiceById(serviceId),
);
