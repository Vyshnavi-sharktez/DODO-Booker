import '../../../shared/repositories/base_repository.dart';
import '../domain/models/dashboard_stats.dart';

class DashboardRepository extends BaseRepository {
  const DashboardRepository(super.supabase);

  Future<DashboardStats> fetchStats(String vendorId) async =>
      throw UnimplementedError();
}
