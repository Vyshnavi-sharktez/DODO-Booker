import '../repositories/i_services_repository.dart';

class RemoveVendorServiceUseCase {
  const RemoveVendorServiceUseCase(this._repository);
  final IServicesRepository _repository;

  Future<void> call(String vendorServiceId) =>
      _repository.removeVendorService(vendorServiceId);
}
