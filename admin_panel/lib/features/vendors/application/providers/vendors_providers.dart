import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/vendors_repository.dart';
import '../../domain/models/vendor.dart';

final vendorsRepositoryProvider = Provider<VendorsRepository>((ref) {
  return VendorsRepository(ref.watch(supabaseClientProvider));
});

class VendorsNotifier extends StateNotifier<AsyncValue<List<Vendor>>> {
  final VendorsRepository _repo;

  VendorsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchVendors);
  }

  Future<void> refresh() => _load();

  Future<void> createVendor({
    required String businessName,
    String? ownerName,
    required String phone,
    required String email,
    required String city,
    String? address,
    required String status,
    required bool isActive,
    double? rating,
    double walletBalance = 0.0,
    double? latitude,
    double? longitude,
  }) async {
    await _repo.createVendor(
      businessName: businessName,
      ownerName: ownerName,
      phone: phone,
      email: email,
      city: city,
      address: address,
      status: status,
      isActive: isActive,
      rating: rating,
      walletBalance: walletBalance,
      latitude: latitude,
      longitude: longitude,
    );
    await _load();
  }

  Future<void> updateVendor(
    String id, {
    required String businessName,
    String? ownerName,
    required String phone,
    required String email,
    required String city,
    String? address,
    required String status,
    required bool isActive,
    double? rating,
    double? walletBalance,
    double? latitude,
    double? longitude,
  }) async {
    await _repo.updateVendor(
      id,
      businessName: businessName,
      ownerName: ownerName,
      phone: phone,
      email: email,
      city: city,
      address: address,
      status: status,
      isActive: isActive,
      rating: rating,
      walletBalance: walletBalance,
      latitude: latitude,
      longitude: longitude,
    );
    await _load();
  }

  Future<void> deleteVendor(String id) async {
    await _repo.deleteVendor(id);
    await _load();
  }

  Future<void> toggleActive(String id, {required bool currentIsActive}) async {
    final newIsActive = !currentIsActive;
    final newStatus = newIsActive ? 'active' : 'inactive';
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((v) => v.id == id
                ? v.copyWith(isActive: newIsActive, status: newStatus)
                : v)
            .toList(),
      );
    }
    try {
      await _repo.updateActive(id, isActive: newIsActive);
    } catch (e) {
      await _load();
      rethrow;
    }
  }
}

final vendorsNotifierProvider =
    StateNotifierProvider<VendorsNotifier, AsyncValue<List<Vendor>>>((ref) {
  return VendorsNotifier(ref.watch(vendorsRepositoryProvider));
});
