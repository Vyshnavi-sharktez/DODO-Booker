import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/coupon_model.dart';

class CouponService {
  final _client = Supabase.instance.client;

  Future<List<CouponModel>> fetchActiveCoupons() async {
    debugPrint('[DODO][Coupon] Loading');
    final data = await _client
        .from('coupons')
        .select()
        .eq('is_active', true)
        .order('created_at', ascending: false);

    final now = DateTime.now();
    var coupons = (data as List<dynamic>)
        .map((r) => CouponModel.fromMap(r as Map<String, dynamic>))
        .where((c) => c.validTo == null || c.validTo!.isAfter(now))
        .toList();

    // ── Min-order threshold filtering ──────────────────────────────────────
    // Any coupon with maxOrderWiseLimit set requires the customer to have
    // at least that many qualifying (non-cancelled/rejected) orders.
    // Coupons that the customer is ineligible for are hidden entirely.
    final thresholdCoupons =
        coupons.where((c) => c.maxOrderWiseLimit != null).toList();
    if (thresholdCoupons.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString('dodo_customer_id');

      int orderCount = 0;
      if (customerId != null) {
        try {
          final result = await _client.rpc(
            'get_customer_order_count',
            params: {'p_customer_id': customerId},
          );
          orderCount = (result as int?) ?? 0;
        } catch (e) {
          debugPrint('[DODO][Coupon] Order count fetch failed: $e');
        }
      }

      coupons = coupons
          .where((c) =>
              c.maxOrderWiseLimit == null || orderCount >= c.maxOrderWiseLimit!)
          .toList();
      debugPrint(
          '[DODO][Coupon] Order count=$orderCount; '
          '${thresholdCoupons.length} threshold coupon(s) evaluated');
    }

    // ── Resolve applicable node names in a single batch query ──────────────
    final nodeIds =
        coupons.expand((c) => c.applicableNodeIds).toSet().toList();

    if (nodeIds.isNotEmpty) {
      final nodeData = await _client
          .from('catalog_nodes')
          .select('id, name')
          .inFilter('id', nodeIds);

      final nameMap = <String, String>{
        for (final n in (nodeData as List<dynamic>))
          (n as Map<String, dynamic>)['id'] as String:
              n['name'] as String,
      };

      return coupons
          .map((c) => c.applicableNodeIds.isEmpty
              ? c
              : c.copyWith(
                  applicableNodeNames: c.applicableNodeIds
                      .map((id) => nameMap[id])
                      .whereType<String>()
                      .toList(),
                ))
          .toList();
    }

    debugPrint('[DODO][Coupon] Loaded ${coupons.length} active coupons');
    return coupons;
  }

  // Server-side coupon validation. Returns the validated discount amount
  // or throws with the server's error message.
  Future<double> validateCoupon({
    required String code,
    required double subtotal,
    required List<String> cartNodeIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final customerId = prefs.getString('dodo_customer_id');
    final result = await _client.rpc('validate_coupon', params: {
      'p_code': code,
      'p_subtotal': subtotal,
      'p_cart_node_ids': cartNodeIds,
      if (customerId != null) 'p_customer_id': customerId,
    });
    final map = Map<String, dynamic>.from(result as Map);
    if (map['valid'] != true) {
      throw Exception(map['error'] as String? ?? 'Coupon is not valid.');
    }
    return (map['discount'] as num).toDouble();
  }

  Future<void> incrementUsedCount(String couponId) async {
    await _client.rpc(
      'increment_coupon_used_count',
      params: {'p_coupon_id': couponId},
    );
    debugPrint(
        '[DODO][Coupon] Incremented used_count for coupon $couponId (atomic RPC)');
  }
}
