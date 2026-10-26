import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/coupon.dart';

class CouponsRepository {
  final SupabaseClient _supabase;

  const CouponsRepository(this._supabase);

  Future<List<Coupon>> fetchCoupons() async {
    final data = await _supabase
        .from('coupons')
        .select('*, coupon_customer_restrictions(customer_id)')
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
    required String applicabilityType,
    required List<String> applicableNodeIds,
    required String customerEligibility,
    required List<String> selectedCustomerIds,
    int? maxOrderWiseLimit,
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
          'applicability_type': applicabilityType,
          'applicable_node_ids': applicableNodeIds,
          'customer_eligibility': customerEligibility,
          'max_order_wise_limit': maxOrderWiseLimit,
        })
        .select()
        .single();
    final couponId = data['id'] as String;
    await _syncCustomerRestrictions(couponId, selectedCustomerIds);
    return Coupon.fromMap({
      ...data,
      'coupon_customer_restrictions': selectedCustomerIds
          .map((id) => {'customer_id': id})
          .toList(),
    });
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
    required String applicabilityType,
    required List<String> applicableNodeIds,
    required String customerEligibility,
    required List<String> selectedCustomerIds,
    int? maxOrderWiseLimit,
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
          'applicability_type': applicabilityType,
          'applicable_node_ids': applicableNodeIds,
          'customer_eligibility': customerEligibility,
          'max_order_wise_limit': maxOrderWiseLimit,
        })
        .eq('id', id)
        .select()
        .single();
    await _syncCustomerRestrictions(id, selectedCustomerIds);
    return Coupon.fromMap({
      ...data,
      'coupon_customer_restrictions': selectedCustomerIds
          .map((cid) => {'customer_id': cid})
          .toList(),
    });
  }

  // Replace all customer restrictions for a coupon with the given list.
  Future<void> _syncCustomerRestrictions(
      String couponId, List<String> customerIds) async {
    await _supabase
        .from('coupon_customer_restrictions')
        .delete()
        .eq('coupon_id', couponId);
    if (customerIds.isNotEmpty) {
      await _supabase.from('coupon_customer_restrictions').insert(
        customerIds.map((cid) => {
          'coupon_id': couponId,
          'customer_id': cid,
        }).toList(),
      );
    }
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
