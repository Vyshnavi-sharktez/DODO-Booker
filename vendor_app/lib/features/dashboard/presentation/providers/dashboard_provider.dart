import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/models/dashboard_stats.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(supabaseClientProvider)),
);

final dashboardStatsProvider =
    FutureProvider.autoDispose<DashboardStats?>((ref) {
  final vendor = ref.watch(currentVendorUserProvider);
  debugPrint('[DASH][Provider] start — vendor_id=${vendor?.id ?? "NULL (not authenticated)"}');
  if (vendor == null) return Future.value(null);
  return ref.read(dashboardRepositoryProvider).fetchStats(vendor.id);
});
