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
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(1);
    final list = data as List;
    if (list.isEmpty) return null;
    return VendorSubscription.fromMap(list.first as Map<String, dynamic>);
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
  // Step 1: purchasePlan   — creates vendor_subscriptions (status=pending_payment)
  //                          + vendor_subscription_payments (status=pending)
  // Step 2 (on success):   activateSubscription — marks payment paid + sub active
  // Step 2 (on failure):   recordPaymentFailure — marks payment failed
  //                          (subscription stays pending_payment for retry)

  /// Creates a subscription in 'pending_payment' status and an associated
  /// pending payment record. Returns the IDs needed to continue the flow.
  Future<PendingPaymentInfo> purchasePlan({
    required String vendorId,
    required SubscriptionPlan plan,
  }) async {
    final amount = (plan.joiningFee ?? 0) + (plan.subscriptionFee ?? 0);

    final subData = await supabase
        .from('vendor_subscriptions')
        .insert({
          'vendor_id': vendorId,
          'plan_id': plan.id,
          'status': 'pending_payment',
        })
        .select()
        .single();
    final subscriptionId = subData['id'] as String;

    final payData = await supabase
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

    return PendingPaymentInfo(
      subscriptionId: subscriptionId,
      paymentId: payData['id'] as String,
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
