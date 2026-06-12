import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/coupon.dart';

class CouponsRepository {
  final SupabaseClient _supabase;

  const CouponsRepository(this._supabase);

  Future<List<Coupon>> fetchCoupons() async {
    final data = await _supabase
        .from('coupons')
        .select()
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => Coupon.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<Coupon> createCoupon({
    required String code,
    String? description,
    required String discountType,
    required double discountValue,
    double? minOrderAmount,
    double? maxDiscountAmount,
    int? usageLimit,
    DateTime? validFrom,
    DateTime? validTo,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('coupons')
        .insert({
          'code': code.toUpperCase(),
          if (description?.isNotEmpty == true) 'description': description,
          'discount_type': discountType,
          'discount_value': discountValue,
          'min_order_amount': minOrderAmount,
          'max_discount_amount': maxDiscountAmount,
          'usage_limit': usageLimit,
          'valid_from': validFrom?.toIso8601String().split('T').first,
          'valid_to': validTo?.toIso8601String().split('T').first,
          'is_active': isActive,
        })
        .select()
        .single();
    return Coupon.fromMap(data);
  }

  Future<Coupon> updateCoupon(
    String id, {
    required String code,
    String? description,
    required String discountType,
    required double discountValue,
    double? minOrderAmount,
    double? maxDiscountAmount,
    int? usageLimit,
    DateTime? validFrom,
    DateTime? validTo,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('coupons')
        .update({
          'code': code.toUpperCase(),
          'description': description?.isNotEmpty == true ? description : null,
          'discount_type': discountType,
          'discount_value': discountValue,
          'min_order_amount': minOrderAmount,
          'max_discount_amount': maxDiscountAmount,
          'usage_limit': usageLimit,
          'valid_from': validFrom?.toIso8601String().split('T').first,
          'valid_to': validTo?.toIso8601String().split('T').first,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return Coupon.fromMap(data);
  }

  Future<void> deleteCoupon(String id) async {
    await _supabase.from('coupons').delete().eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('coupons')
        .update({'is_active': isActive})
        .eq('id', id);
  }
}
