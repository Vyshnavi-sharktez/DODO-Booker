import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/vendor.dart';

class VendorsRepository {
  final SupabaseClient _supabase;

  const VendorsRepository(this._supabase);

  Future<List<Vendor>> fetchVendors() async {
    final data = await _supabase
        .from('vendors')
        .select()
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => Vendor.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<Vendor> createVendor({
    required String businessName,
    String? ownerName,
    required String phone,
    required String email,
    required String city,
    String? address,
    required String status,
    required bool isActive,
    double? rating,
    double walletBalance = 0.0,
  }) async {
    final data = await _supabase
        .from('vendors')
        .insert({
          'business_name': businessName,
          if (ownerName?.isNotEmpty == true) 'owner_name': ownerName,
          'phone': phone,
          'email': email,
          'city': city,
          if (address?.isNotEmpty == true) 'address': address,
          'status': status,
          'is_active': isActive,
          'rating': rating,
          'wallet_balance': walletBalance,
        })
        .select()
        .single();
    return Vendor.fromMap(data);
  }

  Future<Vendor> updateVendor(
    String id, {
    required String businessName,
    String? ownerName,
    required String phone,
    required String email,
    required String city,
    String? address,
    required String status,
    required bool isActive,
    double? rating,
    double? walletBalance,
  }) async {
    final data = await _supabase
        .from('vendors')
        .update({
          'business_name': businessName,
          'owner_name': ownerName?.isNotEmpty == true ? ownerName : null,
          'phone': phone,
          'email': email,
          'city': city,
          'address': address?.isNotEmpty == true ? address : null,
          'status': status,
          'is_active': isActive,
          'rating': rating,
          if (walletBalance != null) 'wallet_balance': walletBalance,
        })
        .eq('id', id)
        .select()
        .single();
    return Vendor.fromMap(data);
  }

  Future<void> deleteVendor(String id) async {
    await _supabase.from('vendors').delete().eq('id', id);
  }

  Future<void> updateActive(String id, {required bool isActive}) async {
    await _supabase
        .from('vendors')
        .update({'is_active': isActive})
        .eq('id', id);
  }
}
