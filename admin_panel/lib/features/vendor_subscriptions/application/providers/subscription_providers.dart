import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/subscription_repository.dart';
import '../../domain/models/subscription_plan.dart';
import '../../domain/models/vendor_subscription.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(supabaseClientProvider));
});

// ── Plans notifier ────────────────────────────────────────────────────────────

class PlansNotifier extends StateNotifier<AsyncValue<List<SubscriptionPlan>>> {
  final SubscriptionRepository _repo;

  PlansNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchPlans);
  }

  Future<void> refresh() => _load();

  Future<void> createPlan({
    required String name,
    String? description,
    required String billingCycle,
    required int durationDays,
    double? joiningFee,
    double? subscriptionFee,
    required Map<String, dynamic> permissions,
    required bool isActive,
    required int sortOrder,
  }) async {
    final created = await _repo.createPlan(
      name: name,
      description: description,
      billingCycle: billingCycle,
      durationDays: durationDays,
      joiningFee: joiningFee,
      subscriptionFee: subscriptionFee,
      permissions: permissions,
      isActive: isActive,
      sortOrder: sortOrder,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([...current, created]);
  }

  Future<void> updatePlan(
    String id, {
    required String name,
    String? description,
    required String billingCycle,
    required int durationDays,
    double? joiningFee,
    double? subscriptionFee,
    required Map<String, dynamic> permissions,
    required bool isActive,
    required int sortOrder,
  }) async {
    final updated = await _repo.updatePlan(
      id,
      name: name,
      description: description,
      billingCycle: billingCycle,
      durationDays: durationDays,
      joiningFee: joiningFee,
      subscriptionFee: subscriptionFee,
      permissions: permissions,
      isActive: isActive,
      sortOrder: sortOrder,
    );
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(current.map((p) => p.id == id ? updated : p).toList());
    }
  }

  Future<void> deletePlan(String id) async {
    await _repo.deletePlan(id);
    await _load();
  }

  Future<void> toggleActive(String id, {required bool currentIsActive}) async {
    final newValue = !currentIsActive;
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((p) => p.id == id ? p.copyWith(isActive: newValue) : p).toList(),
      );
    }
    try {
      await _repo.togglePlanActive(id, isActive: newValue);
    } catch (_) {
      await _load();
      rethrow;
    }
  }
}

final plansNotifierProvider =
    StateNotifierProvider<PlansNotifier, AsyncValue<List<SubscriptionPlan>>>((ref) {
  return PlansNotifier(ref.watch(subscriptionRepositoryProvider));
});

// ── Vendor subscriptions notifier ─────────────────────────────────────────────

class VendorSubscriptionsNotifier
    extends StateNotifier<AsyncValue<List<VendorSubscription>>> {
  final SubscriptionRepository _repo;

  VendorSubscriptionsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchSubscriptions);
  }

  Future<void> refresh() => _load();

  Future<void> updateSubscription(
    String id, {
    required String planId,
    required String status,
    DateTime? startDate,
    DateTime? expiryDate,
    String? notes,
  }) async {
    final updated = await _repo.updateSubscription(
      id,
      planId: planId,
      status: status,
      startDate: startDate,
      expiryDate: expiryDate,
      notes: notes,
    );
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(current.map((s) => s.id == id ? updated : s).toList());
    }
  }

  Future<void> updateStatus(String id, String status) async {
    await _repo.updateSubscriptionStatus(id, status);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((s) => s.id == id ? s.copyWith(status: status) : s).toList(),
      );
    }
  }

  Future<void> renew(String id, {
    required DateTime newExpiryDate,
    required int currentRenewalCount,
  }) async {
    await _repo.renewSubscriptionDirect(
      id,
      newExpiryDate: newExpiryDate,
      currentRenewalCount: currentRenewalCount,
    );
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((s) => s.id == id
            ? s.copyWith(
                status: 'active',
                expiryDate: newExpiryDate,
                renewalCount: currentRenewalCount + 1,
              )
            : s).toList(),
      );
    }
  }

  Future<void> cancel(String id) async {
    await _repo.cancelSubscription(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((s) => s.id == id ? s.copyWith(status: 'cancelled') : s).toList(),
      );
    }
  }

  Future<void> addPayment({
    required String subscriptionId,
    required String vendorId,
    required String paymentType,
    required double amount,
    required String status,
    String? paymentReference,
    DateTime? paidAt,
    String? notes,
  }) async {
    await _repo.addPayment(
      subscriptionId: subscriptionId,
      vendorId: vendorId,
      paymentType: paymentType,
      amount: amount,
      status: status,
      paymentReference: paymentReference,
      paidAt: paidAt,
      notes: notes,
    );
    await _load();
  }
}

final vendorSubscriptionsNotifierProvider = StateNotifierProvider<
    VendorSubscriptionsNotifier, AsyncValue<List<VendorSubscription>>>((ref) {
  return VendorSubscriptionsNotifier(ref.watch(subscriptionRepositoryProvider));
});

// ── Dashboard stats provider ──────────────────────────────────────────────────

final subscriptionDashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.read(subscriptionRepositoryProvider).fetchDashboardStats();
});
