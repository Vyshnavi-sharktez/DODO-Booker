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

  Future<void> updateActive(String id, {required bool isActive}) async {
    await _supabase
        .from('customers')
        .update({'is_active': isActive})
        .eq('id', id);
  }
}
