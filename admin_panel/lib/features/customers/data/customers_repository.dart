import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/customer.dart';

class CustomersRepository {
  final SupabaseClient _supabase;

  const CustomersRepository(this._supabase);

  Future<List<Customer>> fetchCustomers() async {
    final data = await _supabase
        .from('customers')
        .select()
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => Customer.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<Customer> updateCustomer(
    String id, {
    required String fullName,
    required String phone,
    required String email,
    String? profileImageUrl,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('customers')
        .update({
          'full_name': fullName,
          'phone': phone,
          'email': email,
          'profile_image_url':
              profileImageUrl?.isNotEmpty == true ? profileImageUrl : null,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return Customer.fromMap(data);
  }

  Future<Customer> createCustomer({
    required String fullName,
    required String phone,
    required String email,
    String? profileImageUrl,
    required bool isActive,
    List<({
      String line1,
      String area,
      String city,
      String state,
      String pincode,
      String landmark,
      bool isDefault,
    })> addresses = const [],
  }) async {
    // auth_user_id is intentionally omitted — null marks this as admin-created.
    final data = await _supabase
        .from('customers')
        .insert({
          'full_name': fullName,
          'phone': phone,
          'email': email,
          if (profileImageUrl?.isNotEmpty == true)
            'profile_image_url': profileImageUrl,
          'is_active': isActive,
        })
        .select()
        .single();
    final customer = Customer.fromMap(data);

    if (addresses.isNotEmpty) {
      final rows = addresses.map((a) {
        String line2 = a.area;
        if (a.landmark.isNotEmpty) {
          line2 = line2.isNotEmpty
              ? '$line2, Near ${a.landmark}'
              : 'Near ${a.landmark}';
        }
        return {
          'customer_id': customer.id,
          'address_type': 'Home',
          'address_line_1': a.line1,
          if (line2.isNotEmpty) 'address_line_2': line2,
          'city': a.city,
          'state': a.state,
          'pincode': a.pincode,
          'is_default': a.isDefault,
        };
      }).toList();
      await _supabase.from('customer_addresses').insert(rows);
    }

    return customer;
  }

  Future<void> updateActive(String id, {required bool isActive}) async {
    await _supabase
        .from('customers')
        .update({'is_active': isActive})
        .eq('id', id);
  }
}
