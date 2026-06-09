import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../vendors/application/providers/vendors_providers.dart';

class DashboardStats {
  final int totalVendors;
  final int activeVendors;

  const DashboardStats({
    this.totalVendors = 0,
    this.activeVendors = 0,
  });
}

/// Derives dashboard stats from already-loaded providers.
/// Automatically updates whenever vendor CRUD operations complete.
final dashboardStatsProvider = Provider<DashboardStats>((ref) {
  final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
  return DashboardStats(
    totalVendors: vendors.length,
    activeVendors: vendors.where((v) => v.isActive).length,
  );
});
