import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../data/vendor_settlement_repository.dart';
import '../../domain/models/vendor_settlement.dart';

final vendorSettlementRepositoryProvider =
    Provider<VendorSettlementRepository>((ref) {
  return VendorSettlementRepository(ref.watch(supabaseClientProvider));
});

class VendorSettlementHistoryNotifier
    extends StateNotifier<List<VendorSettlement>> {
  VendorSettlementHistoryNotifier() : super([]);

  void addEntry(VendorSettlement entry) {
    state = [entry, ...state];
  }
}

final vendorSettlementHistoryProvider = StateNotifierProvider<
    VendorSettlementHistoryNotifier, List<VendorSettlement>>(
  (ref) => VendorSettlementHistoryNotifier(),
);

final totalWalletBalanceProvider = Provider<double>((ref) {
  final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
  return vendors.fold(0.0, (sum, v) => sum + v.walletBalance);
});

final vendorsWithBalanceCountProvider = Provider<int>((ref) {
  final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
  return vendors.where((v) => v.walletBalance > 0).length;
});

final totalSettledAmountProvider = Provider<double>((ref) {
  final history = ref.watch(vendorSettlementHistoryProvider);
  return history.fold(0.0, (sum, e) => sum + e.amount);
});
