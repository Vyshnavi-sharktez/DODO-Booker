import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/service_availability_areas_repository.dart';
import '../../domain/models/service_availability_area.dart';

final serviceAvailabilityAreasRepositoryProvider =
    Provider<ServiceAvailabilityAreasRepository>((ref) {
  return ServiceAvailabilityAreasRepository(
      ref.watch(supabaseClientProvider));
});

final serviceAvailabilityAreasProvider =
    FutureProvider.autoDispose<List<ServiceAvailabilityArea>>((ref) {
  return ref.watch(serviceAvailabilityAreasRepositoryProvider).fetchAll();
});
