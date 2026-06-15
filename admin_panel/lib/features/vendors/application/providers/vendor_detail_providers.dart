import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/vendor_detail_repository.dart';
import '../../domain/models/vendor.dart';
import '../../domain/models/vendor_detail.dart';

final vendorDetailRepositoryProvider =
    Provider<VendorDetailRepository>((ref) {
  return VendorDetailRepository(ref.watch(supabaseClientProvider));
});

final vendorByIdProvider =
    FutureProvider.autoDispose.family<Vendor, String>((ref, vendorId) {
  return ref.watch(vendorDetailRepositoryProvider).fetchVendorById(vendorId);
});

final vendorDocumentsProvider =
    FutureProvider.autoDispose.family<List<VendorDocument>, String>(
  (ref, vendorId) {
    return ref
        .watch(vendorDetailRepositoryProvider)
        .fetchDocuments(vendorId);
  },
);

final vendorServiceAreasProvider =
    FutureProvider.autoDispose.family<List<VendorServiceArea>, String>(
  (ref, vendorId) {
    return ref
        .watch(vendorDetailRepositoryProvider)
        .fetchServiceAreas(vendorId);
  },
);

final vendorBookingStatsProvider =
    FutureProvider.autoDispose.family<VendorBookingStats, String>(
  (ref, vendorId) {
    return ref
        .watch(vendorDetailRepositoryProvider)
        .fetchBookingStats(vendorId);
  },
);
