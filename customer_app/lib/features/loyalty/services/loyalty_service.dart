import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/loyalty_settings_model.dart';
import '../models/customer_loyalty_model.dart';
import '../models/loyalty_transaction_model.dart';

class LoyaltyService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  Future<String?> getCustomerId() async {
    final phone = (await SharedPreferences.getInstance()).getString(_phoneKey);
    if (phone == null) return null;
    final row = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<LoyaltySettingsModel> getSettings() async {
    final data = await _client
        .from('loyalty_settings')
        .select()
        .limit(1)
        .maybeSingle();
    if (data == null) return LoyaltySettingsModel.defaults;
    return LoyaltySettingsModel.fromJson(data);
  }

  Future<CustomerLoyaltyModel> getCustomerLoyalty() async {
    final customerId = await getCustomerId();
    if (customerId == null) return CustomerLoyaltyModel.empty;
    final data = await _client
        .from('customer_loyalty')
        .select()
        .eq('customer_id', customerId)
        .maybeSingle();
    if (data == null) return CustomerLoyaltyModel.empty;
    return CustomerLoyaltyModel.fromJson(data);
  }

  Future<List<LoyaltyTransactionModel>> getTransactions() async {
    final customerId = await getCustomerId();
    if (customerId == null) return [];
    final data = await _client
        .from('loyalty_transactions')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(50);
    return (data as List)
        .map((e) => LoyaltyTransactionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns the resolved loyalty config JSONB for [serviceId] accessed via
  /// [parentNodeId], or null when no scoped config exists (caller uses global).
  Future<Map<String, dynamic>?> getResolvedLoyaltyConfigForService(
    String serviceId,
    String? parentNodeId,
  ) async {
    debugPrint('[DODO][Loyalty] getResolvedLoyaltyConfigForService: '
        'serviceId=$serviceId  parentNodeId=$parentNodeId');
    if (parentNodeId != null) {
      try {
        final result = await _client.rpc(
          'resolve_catalog_module_config',
          params: {
            'p_module': 'loyalty',
            'p_service_id': serviceId,
            'p_parent_id': parentNodeId,
          },
        );
        debugPrint('[DODO][Loyalty] RPC raw result: $result');
        if (result != null && result is Map) {
          return Map<String, dynamic>.from(result);
        }
      } catch (e) {
        debugPrint('[DODO][Loyalty] RPC exception: $e — falling back to null');
      }
    }
    return null;
  }

  Future<void> recordRedemption({
    required String bookingId,
    required int points,
  }) async {
    final customerId = await getCustomerId();
    if (customerId == null) return;

    final row = await _client
        .from('customer_loyalty')
        .select('available_points, lifetime_redeemed')
        .eq('customer_id', customerId)
        .maybeSingle();

    if (row == null) return;

    final current = row['available_points'] as int? ?? 0;
    final redeemed = row['lifetime_redeemed'] as int? ?? 0;

    final newBalance = (current - points).clamp(0, current);

    await _client
        .from('customer_loyalty')
        .update({
          'available_points': newBalance,
          'lifetime_redeemed': redeemed + points,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('customer_id', customerId);

    await _client.from('loyalty_transactions').insert({
      'customer_id': customerId,
      'booking_id': bookingId,
      'transaction_type': 'REDEEM',
      'points': points,
      'description': 'Redeemed for booking',
    });
  }
}
