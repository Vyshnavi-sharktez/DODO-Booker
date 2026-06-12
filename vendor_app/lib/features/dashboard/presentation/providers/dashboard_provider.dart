import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/models/dashboard_stats.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(supabaseClientProvider)),
);

final dashboardStatsProvider =
    FutureProvider.family<DashboardStats, String>((ref, vendorId) {
  return ref.watch(dashboardRepositoryProvider).fetchStats(vendorId);
});
