import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/address_model.dart';

class AddressService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  Future<String> _getCustomerId() async {
    final phone = (await SharedPreferences.getInstance()).getString(_phoneKey);
    if (phone == null) throw Exception('Not authenticated');
    final row = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .single();
    return row['id'] as String;
  }

  Future<List<AddressModel>> fetchAddresses() async {
    debugPrint('[DODO][Address] Loading addresses');
    final customerId = await _getCustomerId();
    debugPrint('[DODO][Address] Loading for customer_id=$customerId');
    final data = await _client
        .from('customer_addresses')
        .select()
        .eq('customer_id', customerId)
        .order('is_default', ascending: false);
    final list = (data as List)
        .map((e) => AddressModel.fromJson(e as Map<String, dynamic>))
        .toList();
    debugPrint('[DODO][Address] Loaded ${list.length} addresses');
    return list;
  }

  Future<AddressModel> createAddress({
    required String addressType,
    required String addressLine1,
    String? addressLine2,
    required String city,
    required String state,
    required String pincode,
    bool isDefault = false,
  }) async {
    final customerId = await _getCustomerId();
    final payload = {
      'customer_id': customerId,
      'address_type': addressType,
      'address_line_1': addressLine1,
      if (addressLine2 != null && addressLine2.isNotEmpty)
        'address_line_2': addressLine2,
      'city': city,
      'state': state,
      'pincode': pincode,
      'is_default': isDefault,
    };
    debugPrint('[DODO][Address] Insert payload: $payload');
    final data = await _client
        .from('customer_addresses')
        .insert(payload)
        .select()
        .single();
    debugPrint('[DODO][Address] Insert success: id=${data['id']}');
    return AddressModel.fromJson(data);
  }

  Future<AddressModel> updateAddress(
    String id, {
    required String addressType,
    required String addressLine1,
    String? addressLine2,
    required String city,
    required String state,
    required String pincode,
  }) async {
    debugPrint('[DODO][Address] Updating address: id=$id');
    final data = await _client
        .from('customer_addresses')
        .update({
          'address_type': addressType,
          'address_line_1': addressLine1,
          'address_line_2':
              (addressLine2?.isNotEmpty ?? false) ? addressLine2 : null,
          'city': city,
          'state': state,
          'pincode': pincode,
        })
        .eq('id', id)
        .select()
        .single();
    debugPrint('[DODO][Address] Update success: id=$id');
    return AddressModel.fromJson(data);
  }

  Future<void> deleteAddress(String id) async {
    debugPrint('[DODO][Address] Deleting address: id=$id');
    await _client.from('customer_addresses').delete().eq('id', id);
    debugPrint('[DODO][Address] Delete success: id=$id');
  }
}
