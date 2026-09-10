import 'package:flutter/foundation.dart';

import '../../../shared/repositories/base_repository.dart';
import '../domain/models/subscription_plan.dart';
import '../domain/models/vendor_subscription.dart';

class SubscriptionRepository extends BaseRepository {
  const SubscriptionRepository(super.supabase);

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<SubscriptionPlan>> fetchActivePlans() async {
    final data = await supabase
        .from('subscription_plans')
        .select()
        .eq('is_active', true)
        .order('sort_order')
        .order('created_at');
    return (data as List)
        .map((r) => SubscriptionPlan.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<VendorSubscription?> fetchMySubscription(String vendorId) async {
    final data = await supabase
        .from('vendor_subscriptions')
        .select('*, subscription_plans(*), vendor_subscription_payments(*)')
        .eq('vendor_id', vendorId)
        .isFilter('catalog_node_id', null)
        .inFilter('status', ['active', 'pending_payment'])
        .order('created_at', ascending: false)
        .limit(1);
    final list = data as List;
    if (list.isEmpty) return null;
    return VendorSubscription.fromMap(list.first as Map<String, dynamic>);
  }

  Future<List<VendorSubscription>> fetchMyCatalogSubscriptions(
      String vendorId) async {
    final data = await supabase
        .from('vendor_subscriptions')
        .select('*, catalog_nodes(name), vendor_subscription_payments(*)')
        .eq('vendor_id', vendorId)
        .not('catalog_node_id', 'is', null)
        .inFilter('status', ['active', 'pending_payment'])
        .order('created_at', ascending: false);
    return (data as List)
        .map((r) => VendorSubscription.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<SubscriptionPlan>> fetchCatalogSubscriptionOfferings() async {
    final data = await supabase
        .rpc('get_catalog_vendor_subscription_offerings');
    return (data as List).map((r) {
      final row = r as Map<String, dynamic>;
      final config = row['config'];
      final configMap = config is Map<String, dynamic>
          ? config
          : <String, dynamic>{};
      return SubscriptionPlan.fromCatalogConfig(
        nodeId: row['node_id'] as String,
        nodeName: row['node_name'] as String? ?? '',
        config: configMap,
      );
    }).toList();
  }

  Future<void> cancelSubscription(String id) async {
    await supabase
        .from('vendor_subscriptions')
        .update({'status': 'cancelled'})
        .eq('id', id);
  }

  Future<Map<String, String>> fetchSubscriptionSettings() async {
    debugPrint('[DODO][Settings] fetching subscription settings from Supabase…');
    try {
      final data = await supabase
          .from('settings')
          .select('setting_key, setting_value')
          .inFilter('setting_key', [
            'subscription_enabled',
            'subscription_require_active',
            'subscription_allow_free_vendors',
            'subscription_grace_period_days',
            'subscription_reminder_days',
          ]);
      debugPrint('[DODO][Settings] raw response (${(data as List).length} rows): $data');
      final parsed = {
        for (final row in data)
          (row as Map<String, dynamic>)['setting_key'] as String:
              (row['setting_value'] as String?) ?? '',
      };
      debugPrint('[DODO][Settings] parsed map: $parsed');
      debugPrint('[DODO][Settings] subscription_enabled = '
          "${parsed['subscription_enabled']} "
          "(enabled=${parsed['subscription_enabled'] == 'true'})");
      return parsed;
    } catch (e, st) {
      debugPrint('[DODO][Settings] ERROR fetching settings: $e\n$st');
      rethrow;
    }
  }

  // ── Purchase flow ─────────────────────────────────────────────────────────
  //
  // Step 1: purchasePlan   — idempotent entry point for both first purchase
  //                          and payment retry after failure.
  //                          • No existing open global sub  → INSERT new row
  //                          • Existing pending_payment sub → UPDATE plan +
  //                            permissions, create new payment (retry path)
  //                          • Existing active sub          → throws, caller
  //                            shows "already subscribed" message
  // Step 2 (on success):   activateSubscription — marks payment paid + sub active
  // Step 2 (on failure):   recordPaymentFailure — marks payment failed
  //                          (subscription stays pending_payment for retry)

  /// Idempotent purchase entry point.
  ///
  /// For catalog plans the existing first-purchase INSERT path is unchanged.
  /// For global plans, checks for an existing open subscription first to
  /// avoid violating the uq_vs_global_active unique index.
  Future<PendingPaymentInfo> purchasePlan({
    required String vendorId,
    required SubscriptionPlan plan,
  }) async {
    final amount = (plan.joiningFee ?? 0) + (plan.subscriptionFee ?? 0);

    // Catalog subscriptions: no existing-row check needed (each catalog node
    // has its own scoped unique index). Use the original INSERT path.
    if (plan.isCatalogPlan) {
      return _insertNewSubscription(
        vendorId: vendorId,
        plan: plan,
        amount: amount,
        extraFields: {'catalog_node_id': plan.catalogNodeId},
      );
    }

    // Global subscriptions: check for any open row before inserting.
    final existing = await supabase
        .from('vendor_subscriptions')
        .select('id, status')
        .eq('vendor_id', vendorId)
        .isFilter('catalog_node_id', null)
        .inFilter('status', ['pending_payment', 'pending', 'pending_approval'])
        .limit(1);

    final existingList = existing as List;

    if (existingList.isNotEmpty) {
      // Pending row from a previous attempt — reuse it with the new plan.
      final existingId = existingList.first['id'] as String;
      await supabase
          .from('vendor_subscriptions')
          .update({
            'plan_id': plan.id,
            'subscription_permissions': plan.permissions,
          })
          .eq('id', existingId);

      final paymentId = await createRetryPayment(
        subscriptionId: existingId,
        vendorId: vendorId,
        amount: amount,
      );

      return PendingPaymentInfo(
        subscriptionId: existingId,
        paymentId: paymentId,
        amount: amount,
        planDurationDays: plan.durationDays,
        planName: plan.name,
      );
    }

    // Check for an active subscription (renew / upgrade path).
    final active = await supabase
        .from('vendor_subscriptions')
        .select('id')
        .eq('vendor_id', vendorId)
        .isFilter('catalog_node_id', null)
        .eq('status', 'active')
        .limit(1);

    if ((active as List).isNotEmpty) {
      throw Exception(
        'You already have an active subscription. '
        'It will remain active until it expires, after which you can renew '
        'or choose a different plan.',
      );
    }

    // No open subscription — standard first-purchase path.
    return _insertNewSubscription(
      vendorId: vendorId,
      plan: plan,
      amount: amount,
      extraFields: {'plan_id': plan.id},
    );
  }

  /// Inserts a new vendor_subscriptions row and its first payment record.
  Future<PendingPaymentInfo> _insertNewSubscription({
    required String vendorId,
    required SubscriptionPlan plan,
    required double amount,
    required Map<String, dynamic> extraFields,
  }) async {
    final subData = await supabase
        .from('vendor_subscriptions')
        .insert({
          'vendor_id': vendorId,
          'status': 'pending_payment',
          'subscription_permissions': plan.permissions,
          ...extraFields,
        })
        .select()
        .single();
    final subscriptionId = subData['id'] as String;

    final paymentId = await createRetryPayment(
      subscriptionId: subscriptionId,
      vendorId: vendorId,
      amount: amount,
    );

    return PendingPaymentInfo(
      subscriptionId: subscriptionId,
      paymentId: paymentId,
      amount: amount,
      planDurationDays: plan.durationDays,
      planName: plan.name,
    );
  }

  /// Marks the payment as paid and activates the subscription.
  /// Call this after receiving a successful payment callback.
  Future<void> activateSubscription({
    required String subscriptionId,
    required String paymentId,
    required int planDurationDays,
    String? gatewayReference,
  }) async {
    final now = DateTime.now();
    final expiry = now.add(Duration(days: planDurationDays));

    await supabase
        .from('vendor_subscription_payments')
        .update({
          'status': 'paid',
          'paid_at': now.toIso8601String(),
          if (gatewayReference != null) 'payment_reference': gatewayReference,
        })
        .eq('id', paymentId);

    await supabase
        .from('vendor_subscriptions')
        .update({
          'status': 'active',
          'start_date': now.toIso8601String(),
          'expiry_date': expiry.toIso8601String(),
        })
        .eq('id', subscriptionId);
  }

  /// Marks the payment as failed. The subscription stays in 'pending_payment'
  /// so the vendor can retry with a new payment attempt.
  Future<void> recordPaymentFailure({
    required String paymentId,
    String? notes,
  }) async {
    await supabase
        .from('vendor_subscription_payments')
        .update({
          'status': 'failed',
          if (notes != null) 'notes': notes,
        })
        .eq('id', paymentId);
  }

  /// Creates a new payment attempt for an existing pending_payment subscription.
  /// Use when the vendor retries after a previous payment failure.
  Future<String> createRetryPayment({
    required String subscriptionId,
    required String vendorId,
    required double amount,
  }) async {
    final data = await supabase
        .from('vendor_subscription_payments')
        .insert({
          'subscription_id': subscriptionId,
          'vendor_id': vendorId,
          'payment_type': 'subscription_fee',
          'amount': amount,
          'status': 'pending',
        })
        .select()
        .single();
    return data['id'] as String;
  }
}

/// Data passed between purchase flow screens via GoRouter extra.
class PendingPaymentInfo {
  final String subscriptionId;
  final String paymentId;
  final double amount;
  final int planDurationDays;
  final String planName;

  const PendingPaymentInfo({
    required this.subscriptionId,
    required this.paymentId,
    required this.amount,
    required this.planDurationDays,
    required this.planName,
  });
}
