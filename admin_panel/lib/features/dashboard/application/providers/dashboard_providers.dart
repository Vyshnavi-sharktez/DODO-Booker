import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../categories/application/providers/categories_providers.dart';
import '../../../sub_categories/application/providers/sub_categories_providers.dart';
import '../../../services/application/providers/services_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../bookings/application/providers/bookings_providers.dart';
import '../../../coupons/application/providers/coupons_providers.dart';

class DashboardStats {
  final int totalCategories;
  final int totalSubCategories;
  final int totalServices;
  final int totalVendors;
  final int activeVendors;
  final int totalBookings;
  final int totalCoupons;
  final int activeCoupons;

  // Booking status breakdown
  final int bookingsPending;
  final int bookingsAssigned;
  final int bookingsInProgress;
  final int bookingsCompleted;
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
    this.bookingsInProgress = 0,
    this.bookingsCompleted = 0,
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
    bookingsInProgress:
        bookings.where((b) => b.status == 'in_progress').length,
    bookingsCompleted:
        bookings.where((b) => b.status == 'completed').length,
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
