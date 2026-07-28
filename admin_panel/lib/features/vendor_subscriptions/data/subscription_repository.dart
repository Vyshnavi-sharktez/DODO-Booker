import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/subscription_plan.dart';
import '../domain/models/vendor_subscription.dart';

class SubscriptionRepository {
  final SupabaseClient _supabase;

  const SubscriptionRepository(this._supabase);

  // ── Plans ─────────────────────────────────────────────────────────────────

  Future<List<SubscriptionPlan>> fetchPlans() async {
    final data = await _supabase
        .from('subscription_plans')
        .select()
        .order('sort_order')
        .order('created_at');
    return (data as List).map((r) => SubscriptionPlan.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<SubscriptionPlan> createPlan({
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
    final data = await _supabase
        .from('subscription_plans')
        .insert({
          'name': name,
          if (description?.isNotEmpty == true) 'description': description,
          'billing_cycle': billingCycle,
          'duration_days': durationDays,
          'joining_fee': joiningFee,
          'subscription_fee': subscriptionFee,
          'permissions': permissions,
          'is_active': isActive,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return SubscriptionPlan.fromMap(data);
  }

  Future<SubscriptionPlan> updatePlan(
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
    final data = await _supabase
        .from('subscription_plans')
        .update({
          'name': name,
          'description': description?.isNotEmpty == true ? description : null,
          'billing_cycle': billingCycle,
          'duration_days': durationDays,
          'joining_fee': joiningFee,
          'subscription_fee': subscriptionFee,
          'permissions': permissions,
          'is_active': isActive,
          'sort_order': sortOrder,
        })
        .eq('id', id)
        .select()
        .single();
    return SubscriptionPlan.fromMap(data);
  }

  Future<void> deletePlan(String id) async {
    final refs = await _supabase
        .from('vendor_subscriptions')
        .select('id')
        .eq('plan_id', id)
        .limit(1);
    if ((refs as List).isNotEmpty) {
      throw Exception(
        'This plan cannot be deleted because it has vendor subscriptions '
        'linked to it. Deactivate the plan instead.',
      );
    }
    await _supabase.from('subscription_plans').delete().eq('id', id);
  }

  Future<void> togglePlanActive(String id, {required bool isActive}) async {
    await _supabase
        .from('subscription_plans')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  // ── Vendor Subscriptions ──────────────────────────────────────────────────

  Future<List<VendorSubscription>> fetchSubscriptions() async {
    final data = await _supabase
        .from('vendor_subscriptions')
        .select('*, subscription_plans(name), vendors(business_name), catalog_nodes(name), vendor_subscription_payments(*)')
        .order('created_at', ascending: false);
    return (data as List).map((r) => VendorSubscription.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<VendorSubscription> updateSubscription(
    String id, {
    String? planId,
    required String status,
    DateTime? startDate,
    DateTime? expiryDate,
    String? notes,
  }) async {
    final data = await _supabase
        .from('vendor_subscriptions')
        .update({
          if (planId != null) 'plan_id': planId,
          'status': status,
          'start_date': startDate?.toIso8601String(),
          'expiry_date': expiryDate?.toIso8601String(),
          'notes': notes?.isNotEmpty == true ? notes : null,
        })
        .eq('id', id)
        .select('*, subscription_plans(name), vendors(business_name), catalog_nodes(name), vendor_subscription_payments(*)')
        .single();
    return VendorSubscription.fromMap(data);
  }

  Future<void> updateSubscriptionStatus(String id, String status) async {
    await _supabase
        .from('vendor_subscriptions')
        .update({'status': status})
        .eq('id', id);
  }

  Future<void> cancelSubscription(String id) async {
    await _supabase
        .from('vendor_subscriptions')
        .update({'status': 'cancelled'})
        .eq('id', id);
  }

  Future<void> renewSubscriptionDirect(String id, {
    required DateTime newExpiryDate,
    required int currentRenewalCount,
  }) async {
    await _supabase.from('vendor_subscriptions').update({
      'status': 'active',
      'expiry_date': newExpiryDate.toIso8601String(),
      'renewal_count': currentRenewalCount + 1,
    }).eq('id', id);
  }

  // ── Payments ──────────────────────────────────────────────────────────────

  Future<SubscriptionPayment> addPayment({
    required String subscriptionId,
    required String vendorId,
    required String paymentType,
    required double amount,
    required String status,
    String? paymentReference,
    DateTime? paidAt,
    String? notes,
  }) async {
    final data = await _supabase
        .from('vendor_subscription_payments')
        .insert({
          'subscription_id': subscriptionId,
          'vendor_id': vendorId,
          'payment_type': paymentType,
          'amount': amount,
          'status': status,
          if (paymentReference?.isNotEmpty == true) 'payment_reference': paymentReference,
          'paid_at': paidAt?.toIso8601String(),
          if (notes?.isNotEmpty == true) 'notes': notes,
        })
        .select()
        .single();
    return SubscriptionPayment.fromMap(data);
  }

  Future<void> updatePaymentStatus(String paymentId, String status, {DateTime? paidAt}) async {
    await _supabase.from('vendor_subscription_payments').update({
      'status': status,
      if (paidAt != null) 'paid_at': paidAt.toIso8601String(),
    }).eq('id', paymentId);
  }

  // ── Dashboard stats ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchDashboardStats() async {
    final now = DateTime.now().toIso8601String();
    final soon = DateTime.now().add(const Duration(days: 7)).toIso8601String();

    final activeRes = await _supabase
        .from('vendor_subscriptions')
        .select('id')
        .eq('status', 'active');

    final expiringSoonRes = await _supabase
        .from('vendor_subscriptions')
        .select('id')
        .eq('status', 'active')
        .lte('expiry_date', soon)
        .gte('expiry_date', now);

    final expiredRes = await _supabase
        .from('vendor_subscriptions')
        .select('id')
        .eq('status', 'expired');

    final revenueRes = await _supabase
        .from('vendor_subscription_payments')
        .select('amount')
        .eq('status', 'paid');

    double totalRevenue = 0;
    for (final r in (revenueRes as List)) {
      totalRevenue += ((r as Map<String, dynamic>)['amount'] as num?)?.toDouble() ?? 0;
    }

    return {
      'active': (activeRes as List).length,
      'expiring_soon': (expiringSoonRes as List).length,
      'expired': (expiredRes as List).length,
      'total_revenue': totalRevenue,
    };
  }
}
