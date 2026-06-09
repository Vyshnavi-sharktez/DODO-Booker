import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/coupons_repository.dart';
import '../../domain/models/coupon.dart';

final couponsRepositoryProvider = Provider<CouponsRepository>((ref) {
  return CouponsRepository(ref.watch(supabaseClientProvider));
});

class CouponsNotifier extends StateNotifier<AsyncValue<List<Coupon>>> {
  final CouponsRepository _repo;

  CouponsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchCoupons);
  }

  Future<void> refresh() => _load();

  Future<void> createCoupon({
    required String code,
    String? description,
    required String discountType,
    required double discountValue,
    double? minOrderAmount,
    double? minDiscountAmount,
    int? usageLimit,
    DateTime? validFrom,
    DateTime? validTo,
    required bool isActive,
  }) async {
    final created = await _repo.createCoupon(
      code: code,
      description: description,
      discountType: discountType,
      discountValue: discountValue,
      minOrderAmount: minOrderAmount,
      minDiscountAmount: minDiscountAmount,
      usageLimit: usageLimit,
      validFrom: validFrom,
      validTo: validTo,
      isActive: isActive,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([created, ...current]);
  }

  Future<void> updateCoupon(
    String id, {
    required String code,
    String? description,
    required String discountType,
    required double discountValue,
    double? minOrderAmount,
    double? minDiscountAmount,
    int? usageLimit,
    DateTime? validFrom,
    DateTime? validTo,
    required bool isActive,
  }) async {
    final updated = await _repo.updateCoupon(
      id,
      code: code,
      description: description,
      discountType: discountType,
      discountValue: discountValue,
      minOrderAmount: minOrderAmount,
      minDiscountAmount: minDiscountAmount,
      usageLimit: usageLimit,
      validFrom: validFrom,
      validTo: validTo,
      isActive: isActive,
    );
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((c) => c.id == id ? updated : c).toList(),
      );
    }
  }

  Future<void> deleteCoupon(String id) async {
    await _repo.deleteCoupon(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(current.where((c) => c.id != id).toList());
    }
  }

  Future<void> toggleActive(String id, {required bool currentIsActive}) async {
    final newValue = !currentIsActive;
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((c) => c.id == id ? c.copyWith(isActive: newValue) : c)
            .toList(),
      );
    }
    try {
      await _repo.toggleActive(id, isActive: newValue);
    } catch (e) {
      await _load();
      rethrow;
    }
  }
}

final couponsNotifierProvider =
    StateNotifierProvider<CouponsNotifier, AsyncValue<List<Coupon>>>((ref) {
  return CouponsNotifier(ref.watch(couponsRepositoryProvider));
});
