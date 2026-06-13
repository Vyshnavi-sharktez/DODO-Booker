import '../models/assigned_service.dart';
import '../repositories/i_services_repository.dart';

class GetVendorServicesUseCase {
  const GetVendorServicesUseCase(this._repository);
  final IServicesRepository _repository;

  Future<List<AssignedService>> call(String vendorId) =>
      _repository.getVendorServices(vendorId);
}
