import 'package:flutter/foundation.dart';
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
    final coupons = (data as List<dynamic>)
        .map((r) => CouponModel.fromMap(r as Map<String, dynamic>))
        .toList();
    debugPrint('[DODO][Coupon] Loaded ${coupons.length} active coupons');
    return coupons;
  }

  Future<void> incrementUsedCount(String couponId) async {
    // The RPC performs `UPDATE coupons SET used_count = used_count + 1 WHERE id = p_coupon_id`
    // as a single atomic statement inside PostgreSQL. No value is read into Flutter,
    // so two concurrent bookings cannot both read the same count, both add 1, and
    // both write the same result — the previous read-modify-write race condition.
    await _client.rpc(
      'increment_coupon_used_count',
      params: {'p_coupon_id': couponId},
    );
    debugPrint('[DODO][Coupon] Incremented used_count for coupon $couponId (atomic RPC)');
  }
}
