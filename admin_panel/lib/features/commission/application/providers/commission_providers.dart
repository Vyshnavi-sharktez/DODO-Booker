import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/commission_repository.dart';
import '../../domain/models/commission_rule.dart';

final commissionRepositoryProvider = Provider<CommissionRepository>((ref) {
  return CommissionRepository(ref.watch(supabaseClientProvider));
});

final globalCommissionProvider = FutureProvider<CommissionRule?>((ref) {
  return ref.watch(commissionRepositoryProvider).fetchGlobal();
});

final categoryCommissionProvider =
    FutureProvider.family<CommissionRule?, String>((ref, categoryId) {
  return ref.watch(commissionRepositoryProvider).fetchForCategory(categoryId);
});

final vendorCommissionProvider =
    FutureProvider.family<CommissionRule?, String>((ref, vendorId) {
  return ref.watch(commissionRepositoryProvider).fetchForVendor(vendorId);
});

/// Resolved commission for a vendor settlement: vendor → vendor's category → global.
/// Uses resolveForSettlement() so category-level commission is applied even
/// when the settlement dialog has no explicit category in scope.
final resolvedVendorCommissionProvider =
    FutureProvider.family<CommissionRule?, String>((ref, vendorId) {
  return ref.watch(commissionRepositoryProvider).resolveForSettlement(vendorId);
});
