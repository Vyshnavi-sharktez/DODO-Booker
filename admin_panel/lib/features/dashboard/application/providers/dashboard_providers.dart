import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../categories/application/providers/categories_providers.dart';
import '../../../sub_categories/application/providers/sub_categories_providers.dart';
import '../../../services/application/providers/services_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../bookings/application/providers/bookings_providers.dart';
import '../../../coupons/application/providers/coupons_providers.dart';
import '../../../customers/application/providers/customers_providers.dart';
import '../../../dodo_teams/application/providers/dodo_teams_providers.dart';
import '../../../vendor_settlement/application/providers/vendor_settlement_providers.dart';

// ── Legacy overview stats (kept for backward compatibility) ───────────────────

class DashboardStats {
  final int totalCategories;
  final int totalSubCategories;
  final int totalServices;
  final int totalVendors;
  final int activeVendors;
  final int totalBookings;
  final int totalCoupons;
  final int activeCoupons;

  // Booking status breakdown (event-driven lifecycle)
  final int bookingsPending;
  final int bookingsAssigned;
  final int bookingsAccepted;
  final int bookingsOnTheWay;
  final int bookingsArrived;
  final int bookingsInProgress;
  final int bookingsCompleted;
  final int bookingsRejected;
  final int bookingsCancelled;

  const DashboardStats({
    this.totalCategories = 0,
    this.totalSubCategories = 0,
    this.totalServices = 0,
    this.totalVendors = 0,
    this.activeVendors = 0,
    this.totalBookings = 0,
    this.totalCoupons = 0,
    this.activeCoupons = 0,
    this.bookingsPending = 0,
    this.bookingsAssigned = 0,
    this.bookingsAccepted = 0,
    this.bookingsOnTheWay = 0,
    this.bookingsArrived = 0,
    this.bookingsInProgress = 0,
    this.bookingsCompleted = 0,
    this.bookingsRejected = 0,
    this.bookingsCancelled = 0,
  });
}

/// Derives all dashboard statistics from already-loaded feature providers.
/// Auto-updates whenever any CRUD operation completes in any module.
final dashboardStatsProvider = Provider<DashboardStats>((ref) {
  final categories =
      ref.watch(categoriesNotifierProvider).valueOrNull ?? [];
  final subCategories =
      ref.watch(subCategoriesNotifierProvider).valueOrNull ?? [];
  final services = ref.watch(servicesNotifierProvider).valueOrNull ?? [];
  final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
  final coupons = ref.watch(couponsNotifierProvider).valueOrNull ?? [];

  return DashboardStats(
    totalCategories: categories.length,
    totalSubCategories: subCategories.length,
    totalServices: services.length,
    totalVendors: vendors.length,
    activeVendors: vendors.where((v) => v.isActive).length,
    totalBookings: bookings.length,
    totalCoupons: coupons.length,
    activeCoupons: coupons.where((c) => c.isActive && !c.isExpired).length,
    bookingsPending:
        bookings.where((b) => b.status == 'pending').length,
    bookingsAssigned:
        bookings.where((b) => b.status == 'assigned').length,
    bookingsAccepted:
        bookings.where((b) => b.status == 'accepted').length,
    bookingsOnTheWay:
        bookings.where((b) => b.status == 'on_the_way').length,
    bookingsArrived:
        bookings.where((b) => b.status == 'arrived').length,
    bookingsInProgress:
        bookings.where((b) => b.status == 'in_progress').length,
    bookingsCompleted:
        bookings.where((b) => b.status == 'completed').length,
    bookingsRejected:
        bookings.where((b) => b.status == 'rejected').length,
    bookingsCancelled:
        bookings.where((b) => b.status == 'cancelled').length,
  );
});

/// True when any data source is still loading.
final dashboardIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(categoriesNotifierProvider).isLoading ||
      ref.watch(subCategoriesNotifierProvider).isLoading ||
      ref.watch(servicesNotifierProvider).isLoading ||
      ref.watch(vendorsNotifierProvider).isLoading ||
      ref.watch(bookingsNotifierProvider).isLoading ||
      ref.watch(couponsNotifierProvider).isLoading;
});

// ── Revenue (derived from completed bookings in memory) ───────────────────────

class DashboardRevenue {
  final double today;
  final double thisWeek;
  final double thisMonth;
  const DashboardRevenue({
    this.today = 0,
    this.thisWeek = 0,
    this.thisMonth = 0,
  });
}

final dashboardRevenueProvider = Provider<DashboardRevenue>((ref) {
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
  final monthStart = DateTime(now.year, now.month, 1);

  double today = 0, thisWeek = 0, thisMonth = 0;
  for (final b in bookings) {
    if (b.status != 'completed') continue;
    final date = b.createdAt;
    if (date == null) continue;
    if (!date.isBefore(monthStart)) thisMonth += b.totalAmount;
    if (!date.isBefore(weekStart)) thisWeek += b.totalAmount;
    if (!date.isBefore(todayStart)) today += b.totalAmount;
  }
  return DashboardRevenue(today: today, thisWeek: thisWeek, thisMonth: thisMonth);
});

// ── Customer stats (derived from in-memory lists) ─────────────────────────────

class DashboardCustomerStats {
  final int total;
  final int newThisMonth;
  final int returning;
  const DashboardCustomerStats({
    this.total = 0,
    this.newThisMonth = 0,
    this.returning = 0,
  });
}

final dashboardCustomerStatsProvider = Provider<DashboardCustomerStats>((ref) {
  final customers = ref.watch(customersNotifierProvider).valueOrNull ?? [];
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);

  final newThisMonth = customers
      .where((c) => c.createdAt != null && !c.createdAt!.isBefore(monthStart))
      .length;

  final completedPerCustomer = <String, int>{};
  for (final b in bookings) {
    if (b.status == 'completed' && b.customerId.isNotEmpty) {
      completedPerCustomer[b.customerId] =
          (completedPerCustomer[b.customerId] ?? 0) + 1;
    }
  }
  final returning =
      completedPerCustomer.values.where((count) => count > 1).length;

  return DashboardCustomerStats(
    total: customers.length,
    newThisMonth: newThisMonth,
    returning: returning,
  );
});

// ── Pending actions (derived from in-memory lists) ────────────────────────────

class DashboardPendingActions {
  final int unassignedBookings;
  final int pendingSettlements;
  final int pendingVendorVerifications;
  const DashboardPendingActions({
    this.unassignedBookings = 0,
    this.pendingSettlements = 0,
    this.pendingVendorVerifications = 0,
  });
}

final dashboardPendingActionsProvider = Provider<DashboardPendingActions>((ref) {
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
  final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
  final pendingCount = ref.watch(vendorsAwaitingPaymentCountProvider);

  final unassigned = bookings
      .where((b) => b.status == 'pending' && b.isUnassigned)
      .length;

  final pendingVerification =
      vendors.where((v) => v.status == 'pending').length;

  return DashboardPendingActions(
    unassignedBookings: unassigned,
    pendingSettlements: pendingCount,
    pendingVendorVerifications: pendingVerification,
  );
});

// ── Vendor activity breakdown ─────────────────────────────────────────────────

class DashboardVendorActivity {
  final int activeVendors;
  final int totalTeams;
  final int availableTeams;
  final int vendorsOnJobs;
  const DashboardVendorActivity({
    this.activeVendors = 0,
    this.totalTeams = 0,
    this.availableTeams = 0,
    this.vendorsOnJobs = 0,
  });
}

final dashboardVendorActivityProvider = Provider<DashboardVendorActivity>((ref) {
  final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
  final teams = ref.watch(dodoTeamsNotifierProvider).valueOrNull ?? [];
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];

  final activeVendors = vendors.where((v) => v.isActive).length;
  final availableTeams =
      teams.where((t) => t.status == 'Available' && t.isActive).length;

  final vendorsOnJobs = bookings
      .where((b) => b.status == 'in_progress' && b.vendorId.isNotEmpty)
      .map((b) => b.vendorId)
      .toSet()
      .length;

  return DashboardVendorActivity(
    activeVendors: activeVendors,
    totalTeams: teams.length,
    availableTeams: availableTeams,
    vendorsOnJobs: vendorsOnJobs,
  );
});

// ── System health ─────────────────────────────────────────────────────────────

class DashboardSystemHealth {
  final int activeServices;
  final int activeCategories;
  final int activeCoupons;
  const DashboardSystemHealth({
    this.activeServices = 0,
    this.activeCategories = 0,
    this.activeCoupons = 0,
  });
}

final dashboardSystemHealthProvider = Provider<DashboardSystemHealth>((ref) {
  final services = ref.watch(servicesNotifierProvider).valueOrNull ?? [];
  final categories = ref.watch(categoriesNotifierProvider).valueOrNull ?? [];
  final coupons = ref.watch(couponsNotifierProvider).valueOrNull ?? [];

  return DashboardSystemHealth(
    activeServices: services.where((s) => s.isActive).length,
    activeCategories: categories.where((c) => c.isActive).length,
    activeCoupons: coupons.where((c) => c.isActive && !c.isExpired).length,
  );
});

// ── Top 5 services by completed booking items ─────────────────────────────────

class TopServiceStat {
  final String serviceId;
  final String serviceName;
  final int bookingCount;
  const TopServiceStat({
    required this.serviceId,
    required this.serviceName,
    required this.bookingCount,
  });
}

final dashboardTopServicesProvider = Provider<List<TopServiceStat>>((ref) {
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];

  final countByService = <String, ({String name, int count})>{};
  for (final b in bookings) {
    if (b.status != 'completed') continue;
    for (final item in b.items) {
      if (item.serviceId.isEmpty) continue;
      final existing = countByService[item.serviceId];
      countByService[item.serviceId] = (
        name: (existing?.name.isNotEmpty == true)
            ? existing!.name
            : (item.serviceName.isNotEmpty ? item.serviceName : 'Unknown'),
        count: (existing?.count ?? 0) + item.quantity,
      );
    }
  }

  final sorted = countByService.entries.toList()
    ..sort((a, b) => b.value.count.compareTo(a.value.count));

  return sorted.take(5).map((e) => TopServiceStat(
        serviceId: e.key,
        serviceName: e.value.name,
        bookingCount: e.value.count,
      )).toList();
});

// ── Top 5 vendor performance (by completed jobs) ──────────────────────────────

class VendorPerformanceStat {
  final String vendorId;
  final String vendorName;
  final int completedJobs;
  const VendorPerformanceStat({
    required this.vendorId,
    required this.vendorName,
    required this.completedJobs,
  });
}

final dashboardVendorPerfProvider = Provider<List<VendorPerformanceStat>>((ref) {
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
  final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];

  final vendorMap = {for (final v in vendors) v.id: v.businessName};

  final countByVendor = <String, int>{};
  for (final b in bookings) {
    if (b.status == 'completed' && b.vendorId.isNotEmpty) {
      countByVendor[b.vendorId] = (countByVendor[b.vendorId] ?? 0) + 1;
    }
  }

  final sorted = countByVendor.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return sorted.take(5).map((e) => VendorPerformanceStat(
        vendorId: e.key,
        vendorName: vendorMap[e.key] ?? 'Unknown Vendor',
        completedJobs: e.value,
      )).toList();
});

// ── Daily revenue for last 30 days ────────────────────────────────────────────

class DailyRevenueStat {
  final DateTime date;
  final double amount;
  const DailyRevenueStat({required this.date, required this.amount});
}

final dashboardDailyRevenueProvider = Provider<List<DailyRevenueStat>>((ref) {
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final cutoff = todayStart.subtract(const Duration(days: 29));

  final daily = <String, double>{};
  for (final b in bookings) {
    if (b.status != 'completed') continue;
    final date = b.createdAt;
    if (date == null || date.isBefore(cutoff)) continue;
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    daily[key] = (daily[key] ?? 0) + b.totalAmount;
  }

  return List.generate(30, (i) {
    final date = cutoff.add(Duration(days: i));
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return DailyRevenueStat(date: date, amount: daily[key] ?? 0);
  });
});
