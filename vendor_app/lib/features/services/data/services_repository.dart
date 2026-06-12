import '../../../shared/repositories/base_repository.dart';
import '../domain/models/assigned_service.dart';

class ServicesRepository extends BaseRepository {
  const ServicesRepository(super.supabase);

  Future<List<AssignedService>> fetchVendorServices(
    String vendorId,
  ) async =>
      throw UnimplementedError();
}
