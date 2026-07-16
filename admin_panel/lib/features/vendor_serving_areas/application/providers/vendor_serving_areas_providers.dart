import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/vendor_serving_areas_repository.dart';
import '../../domain/models/vendor_serving_area.dart';

final vendorServingAreasRepositoryProvider =
    Provider<VendorServingAreasRepository>((ref) {
  return VendorServingAreasRepository(ref.watch(supabaseClientProvider));
});

final vendorServingAreasProvider =
    FutureProvider.autoDispose<List<VendorServingArea>>((ref) {
  return ref.watch(vendorServingAreasRepositoryProvider).fetchAll();
});

final vendorAssignedAreaIdsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, vendorId) {
  return ref
      .watch(vendorServingAreasRepositoryProvider)
      .fetchAssignedAreaIds(vendorId);
});

/// Map of {serving_area_id → vendor_count} — single query, no N+1.
final areaAssignmentCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref
      .watch(vendorServingAreasRepositoryProvider)
      .fetchAllAssignmentCounts();
});

/// Vendor summaries for a specific serving area.
final vendorsByAreaProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, areaId) {
  return ref
      .watch(vendorServingAreasRepositoryProvider)
      .fetchVendorsForArea(areaId);
});

/// `{serving_area_id → Set(vendor_id)}` for every assignment row.
final allVendorAreaAssignmentsProvider =
    FutureProvider.autoDispose<Map<String, Set<String>>>((ref) {
  return ref
      .watch(vendorServingAreasRepositoryProvider)
      .fetchAllAssignments();
});

/// Full VendorServingArea objects assigned to a given vendor.
final vendorAssignedAreasProvider =
    FutureProvider.autoDispose.family<List<VendorServingArea>, String>(
        (ref, vendorId) {
  return ref
      .watch(vendorServingAreasRepositoryProvider)
      .fetchAssignedAreasForVendor(vendorId);
});
