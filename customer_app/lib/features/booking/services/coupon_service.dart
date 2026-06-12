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
    final row = await _client
        .from('coupons')
        .select('used_count')
        .eq('id', couponId)
        .single();
    final current = (row['used_count'] as int?) ?? 0;
    await _client
        .from('coupons')
        .update({'used_count': current + 1})
        .eq('id', couponId);
    debugPrint('[DODO][Coupon] Incremented used_count for coupon $couponId → ${current + 1}');
  }
}
