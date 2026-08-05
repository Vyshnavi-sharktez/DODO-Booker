import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/service_warranty_model.dart';
import 'warranty_service.dart';

final warrantyServiceProvider = Provider<WarrantyService>((ref) {
  return WarrantyService();
});

final bookingWarrantyProvider =
    FutureProvider.family<ServiceWarrantyModel?, String>((ref, bookingId) async {
  final service = ref.watch(warrantyServiceProvider);
  return service.fetchWarrantyByBookingId(bookingId);
});

final customerWarrantiesProvider =
    FutureProvider<List<ServiceWarrantyModel>>((ref) async {
  final service = ref.watch(warrantyServiceProvider);
  return service.fetchCustomerWarranties();
});

final reworkImagesGroupedProvider =
    FutureProvider.family<Map<String, List<String>>, String>((ref, reworkBookingId) async {
  final service = ref.watch(warrantyServiceProvider);
  return service.fetchGroupedReworkImages(reworkBookingId);
});
