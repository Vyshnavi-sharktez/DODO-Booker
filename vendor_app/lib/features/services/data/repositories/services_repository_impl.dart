import '../../domain/models/assigned_service.dart';
import '../../domain/models/catalog_service.dart';
import '../../domain/repositories/i_services_repository.dart';
import '../datasources/services_remote_datasource.dart';

class ServicesRepositoryImpl implements IServicesRepository {
  const ServicesRepositoryImpl(this._datasource);
  final ServicesRemoteDatasource _datasource;

  @override
  Future<List<AssignedService>> getVendorServices(String vendorId) async {
    final rows = await _datasource.fetchVendorServices(vendorId);
    return rows.map(AssignedService.fromMap).toList();
  }

  @override
  Future<List<CatalogService>> getCatalogServices() async {
    final rows = await _datasource.fetchCatalogServices();
    return rows.map(CatalogService.fromMap).toList();
  }

  @override
  Future<void> assignServices(String vendorId, List<String> serviceIds) =>
      _datasource.assignServices(vendorId, serviceIds);

  @override
  Future<void> toggleService(String vendorServiceId, bool isActive) =>
      _datasource.toggleService(vendorServiceId, isActive);
}
