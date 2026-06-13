import '../models/assigned_service.dart';
import '../models/catalog_service.dart';

abstract class IServicesRepository {
  Future<List<AssignedService>> getVendorServices(String vendorId);
  Future<List<CatalogService>> getCatalogServices();
  Future<void> assignServices(String vendorId, List<String> serviceIds);
  Future<void> toggleService(String vendorServiceId, bool isActive);
}
