import '../repositories/i_services_repository.dart';

class ToggleServiceUseCase {
  const ToggleServiceUseCase(this._repository);
  final IServicesRepository _repository;

  Future<void> call(String vendorServiceId, bool isActive) =>
      _repository.toggleService(vendorServiceId, isActive);
}
