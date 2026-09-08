import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/datasources/services_remote_datasource.dart';
import '../../data/repositories/services_repository_impl.dart';
import '../../domain/models/assigned_service.dart';
import '../../domain/models/catalog_service.dart';
import '../../domain/models/vendor_service_request_model.dart';
import '../../domain/repositories/i_services_repository.dart';
import '../../domain/usecases/assign_services_usecase.dart';
import '../../domain/usecases/get_catalog_services_usecase.dart';
import '../../domain/usecases/get_vendor_services_usecase.dart';
import '../../domain/usecases/remove_vendor_service_usecase.dart';
import '../../domain/usecases/toggle_service_usecase.dart';

// ── DI chain ─────────────────────────────────────────────────────────────────

final servicesDatasourceProvider = Provider<ServicesRemoteDatasource>(
  (ref) => ServicesRemoteDatasource(ref.watch(supabaseClientProvider)),
);

final servicesRepositoryProvider = Provider<IServicesRepository>(
  (ref) => ServicesRepositoryImpl(ref.watch(servicesDatasourceProvider)),
);

final getVendorServicesUseCaseProvider = Provider<GetVendorServicesUseCase>(
  (ref) => GetVendorServicesUseCase(ref.watch(servicesRepositoryProvider)),
);

final getCatalogServicesUseCaseProvider = Provider<GetCatalogServicesUseCase>(
  (ref) => GetCatalogServicesUseCase(ref.watch(servicesRepositoryProvider)),
);

final assignServicesUseCaseProvider = Provider<AssignServicesUseCase>(
  (ref) => AssignServicesUseCase(ref.watch(servicesRepositoryProvider)),
);

final toggleServiceUseCaseProvider = Provider<ToggleServiceUseCase>(
  (ref) => ToggleServiceUseCase(ref.watch(servicesRepositoryProvider)),
);

final removeVendorServiceUseCaseProvider = Provider<RemoveVendorServiceUseCase>(
  (ref) => RemoveVendorServiceUseCase(ref.watch(servicesRepositoryProvider)),
);

// ── Data providers ────────────────────────────────────────────────────────────

final vendorServicesProvider =
    FutureProvider.autoDispose<List<AssignedService>>((ref) {
  final user = ref.watch(currentVendorUserProvider);
  if (user == null) return Future.value([]);
  return ref.read(getVendorServicesUseCaseProvider).call(user.id);
});

final catalogServicesProvider =
    FutureProvider.autoDispose<List<CatalogService>>(
  (ref) => ref.read(getCatalogServicesUseCaseProvider).call(),
);

// ── Catalog parent-name map for root-category resolution ─────────────────────

/// nodeName → parentName (null when the node is itself a root category).
/// Built from non-bookable nodes only (categories + sub-categories) using the
/// same [name] and [parent_name] columns already proven by catalogServicesProvider.
/// The vendor All Services view walks this map client-side to find each
/// service's root category — no id-based lookups required.
final catalogParentMapProvider = FutureProvider.autoDispose<Map<String, String?>>(
  (ref) async {
    final rows =
        await ref.read(servicesDatasourceProvider).fetchCatalogTree();
    return {
      for (final row in rows)
        (row['name'] as String? ?? ''): row['parent_name'] as String?,
    };
  },
);

final myServiceRequestsProvider =
    FutureProvider.autoDispose<List<VendorServiceRequestModel>>((ref) async {
  final user = ref.watch(currentVendorUserProvider);
  if (user == null) return [];
  final rows = await ref
      .read(servicesDatasourceProvider)
      .fetchMyServiceRequests(user.id);
  return rows.map(VendorServiceRequestModel.fromMap).toList();
});

final vendorTrendingServicesProvider = FutureProvider<List<CatalogService>>(
  (ref) async {
    final maps =
        await ref.read(servicesDatasourceProvider).fetchTrendingServices();
    return maps.map(CatalogService.fromMap).toList();
  },
);

// ── Action notifiers ──────────────────────────────────────────────────────────

class AssignServicesNotifier extends StateNotifier<AsyncValue<void>> {
  AssignServicesNotifier(this._useCase) : super(const AsyncValue.data(null));
  final AssignServicesUseCase _useCase;

  Future<void> assign(String vendorId, List<String> serviceIds) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _useCase(vendorId, serviceIds),
    );
  }
}

final assignServicesProvider = StateNotifierProvider<
    AssignServicesNotifier, AsyncValue<void>>(
  (ref) => AssignServicesNotifier(ref.read(assignServicesUseCaseProvider)),
);
