import '../models/catalog_service.dart';
import '../repositories/i_services_repository.dart';

class GetCatalogServicesUseCase {
  const GetCatalogServicesUseCase(this._repository);
  final IServicesRepository _repository;

  Future<List<CatalogService>> call() => _repository.getCatalogServices();
}
