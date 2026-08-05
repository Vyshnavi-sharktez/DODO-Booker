import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/repositories/vendor_tiers_repository.dart';
import '../../domain/models/vendor_tier.dart';

final vendorTiersRepositoryProvider = Provider<VendorTiersRepository>((ref) {
  return VendorTiersRepository(ref.watch(supabaseClientProvider));
});

class VendorTiersNotifier extends StateNotifier<AsyncValue<List<VendorTier>>> {
  final VendorTiersRepository _repository;

  VendorTiersNotifier(this._repository) : super(const AsyncValue.loading()) {
    fetchTiers();
  }

  Future<void> fetchTiers() async {
    state = const AsyncValue.loading();
    try {
      final tiers = await _repository.getVendorTiers();
      state = AsyncValue.data(tiers);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createTier(VendorTier tier) async {
    try {
      await _repository.createVendorTier(tier);
      await fetchTiers();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> updateTier(VendorTier tier) async {
    try {
      await _repository.updateVendorTier(tier);
      await fetchTiers();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> deleteTier(String id) async {
    try {
      await _repository.deleteVendorTier(id);
      await fetchTiers();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> toggleActiveStatus(VendorTier tier) async {
    final updated = tier.copyWith(isActive: !tier.isActive);
    await updateTier(updated);
  }

  Future<void> reorderTiers(int oldIndex, int newIndex) async {
    final currentData = state.value;
    if (currentData == null) return;

    final items = List<VendorTier>.from(currentData);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    // Optimistic UI update
    state = AsyncValue.data(items);

    try {
      await _repository.updateTierPriorities(items);
      await fetchTiers();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      await fetchTiers(); // Revert on failure
    }
  }

  Future<int> evaluateAllVendors() async {
    final count = await _repository.evaluateAllVendors();
    await fetchTiers();
    return count;
  }
}

final vendorTiersNotifierProvider = StateNotifierProvider<
    VendorTiersNotifier, AsyncValue<List<VendorTier>>>((ref) {
  return VendorTiersNotifier(ref.watch(vendorTiersRepositoryProvider));
});
