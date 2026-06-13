import '../repositories/i_services_repository.dart';

class AssignServicesUseCase {
  const AssignServicesUseCase(this._repository);
  final IServicesRepository _repository;

  Future<void> call(String vendorId, List<String> serviceIds) =>
      _repository.assignServices(vendorId, serviceIds);
}
