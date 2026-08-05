import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/warranties_repository.dart';
import '../domain/models/service_warranty.dart';

final warrantiesRepositoryProvider = Provider<WarrantiesRepository>((ref) {
  return WarrantiesRepository(Supabase.instance.client);
});

final adminWarrantiesProvider =
    FutureProvider.autoDispose<List<ServiceWarranty>>((ref) async {
  final repository = ref.watch(warrantiesRepositoryProvider);
  return repository.fetchWarrantyClaims();
});

final adminAnalyticsWarrantiesProvider =
    FutureProvider.autoDispose<List<ServiceWarranty>>((ref) async {
  final repository = ref.watch(warrantiesRepositoryProvider);
  return repository.fetchAnalyticsWarranties();
});

final claimEvidenceImagesProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, reworkBookingId) async {
  if (reworkBookingId.isEmpty) return [];
  final repository = ref.watch(warrantiesRepositoryProvider);
  return repository.fetchEvidenceImages(reworkBookingId);
});

final reworkImagesGroupedProvider = FutureProvider.autoDispose
    .family<Map<String, List<String>>, String>((ref, reworkBookingId) async {
  if (reworkBookingId.isEmpty) {
    return {'evidence': [], 'before': [], 'after': []};
  }
  final repository = ref.watch(warrantiesRepositoryProvider);
  return repository.fetchReworkImagesGrouped(reworkBookingId);
});
