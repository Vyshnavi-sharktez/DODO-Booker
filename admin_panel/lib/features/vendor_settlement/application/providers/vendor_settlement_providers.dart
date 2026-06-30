import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/vendor_settlement_repository.dart';
import '../../domain/models/vendor_earnings_summary.dart';
import '../../domain/models/vendor_settlement.dart';

// ── Repository ─────────────────────────────────────────────────────────────────

final vendorSettlementRepositoryProvider =
    Provider<VendorSettlementRepository>((ref) {
  return VendorSettlementRepository(ref.watch(supabaseClientProvider));
});

// ── Earnings summaries (main table) ────────────────────────────────────────────

class VendorSettlementNotifier
    extends StateNotifier<AsyncValue<List<VendorEarningsSummary>>> {
  final VendorSettlementRepository _repo;

  VendorSettlementNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchEarningsSummaries);
  }

  Future<void> refresh() => _load();

  Future<void> createSettlement({
    required String vendorId,
    required String vendorName,
    required double amount,
    required int completedJobsCount,
    required String settledBy,
    String? paymentMethod,
    String? referenceNumber,
    String? notes,
  }) async {
    await _repo.createSettlement(
      vendorId: vendorId,
      vendorName: vendorName,
      amount: amount,
      completedJobsCount: completedJobsCount,
      settledBy: settledBy,
      paymentMethod: paymentMethod,
      referenceNumber: referenceNumber,
      notes: notes,
    );
    await _load();
  }
}

final vendorSettlementNotifierProvider = StateNotifierProvider<
    VendorSettlementNotifier, AsyncValue<List<VendorEarningsSummary>>>(
  (ref) => VendorSettlementNotifier(ref.watch(vendorSettlementRepositoryProvider)),
);

// ── Per-vendor summary (used in vendor details page) ───────────────────────────

final vendorPendingSettlementProvider =
    FutureProvider.family<VendorEarningsSummary?, String>((ref, vendorId) async {
  final repo = ref.watch(vendorSettlementRepositoryProvider);
  return repo.fetchEarningsSummaryForVendor(vendorId);
});

// ── Settlement history ─────────────────────────────────────────────────────────

final settlementHistoryProvider =
    FutureProvider<List<VendorSettlement>>((ref) async {
  final repo = ref.watch(vendorSettlementRepositoryProvider);
  return repo.fetchSettlements();
});

final vendorSettlementHistoryProvider =
    FutureProvider.family<List<VendorSettlement>, String>((ref, vendorId) async {
  final repo = ref.watch(vendorSettlementRepositoryProvider);
  return repo.fetchSettlements(vendorId: vendorId);
});

// ── Summary stats ──────────────────────────────────────────────────────────────

final totalPendingSettlementProvider = Provider<double>((ref) {
  final summaries =
      ref.watch(vendorSettlementNotifierProvider).valueOrNull ?? [];
  return summaries.fold(0.0, (sum, s) => sum + s.pendingSettlement);
});

final vendorsAwaitingPaymentCountProvider = Provider<int>((ref) {
  final summaries =
      ref.watch(vendorSettlementNotifierProvider).valueOrNull ?? [];
  return summaries.where((s) => s.pendingSettlement > 0).length;
});

final thisMonthSettlementStatsProvider =
    FutureProvider<(double, int)>((ref) async {
  final repo = ref.watch(vendorSettlementRepositoryProvider);
  return repo.fetchThisMonthStats();
});
