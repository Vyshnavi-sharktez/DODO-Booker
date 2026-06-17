import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';

class CartSyncService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  Future<String?> _customerId() async {
    try {
      final phone =
          (await SharedPreferences.getInstance()).getString(_phoneKey);
      debugPrint('[DODO][CartSync][3] phone from SharedPreferences: $phone');
      if (phone == null) {
        debugPrint('[DODO][CartSync][3] phone is NULL — user not logged in, sync skipped');
        return null;
      }
      debugPrint('[DODO][CartSync][4] querying customers WHERE phone=$phone');
      final row = await _client
          .from('customers')
          .select('id')
          .eq('phone', phone)
          .maybeSingle();
      debugPrint('[DODO][CartSync][5] customer row returned: $row');
      final id = row?['id'] as String?;
      debugPrint('[DODO][CartSync][3] _customerId() resolved to: $id');
      return id;
    } catch (e) {
      debugPrint('[DODO][CartSync] _customerId EXCEPTION: $e — type: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> upsertItem(CartItem item) async {
    try {
      final customerId = await _customerId();
      if (customerId == null) {
        debugPrint('[DODO][CartSync][5] upsertItem aborted — customerId is null');
        return;
      }
      final payload = {
        'customer_id': customerId,
        'service_id': item.serviceId,
        'service_name': item.serviceName,
        'unit_price': item.unitPrice,
        'quantity': item.quantity,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      debugPrint('[DODO][CartSync][5] upsert payload: $payload');
      debugPrint(
        '[DODO][CartSync] supabaseUser=${Supabase.instance.client.auth.currentUser?.id}',
      );
      final response = await _client.from('cart_items').upsert(
        payload,
        onConflict: 'customer_id,service_id',
      );
      debugPrint('[DODO][CartSync][6] upsert response: $response');
    } catch (e) {
      debugPrint('[DODO][CartSync][7] upsertItem EXCEPTION: $e');
      debugPrint('[DODO][CartSync][7] exception type: ${e.runtimeType}');
    }
  }

  Future<void> deleteItem(String serviceId) async {
    try {
      final customerId = await _customerId();
      if (customerId == null) return;
      await _client
          .from('cart_items')
          .delete()
          .eq('customer_id', customerId)
          .eq('service_id', serviceId);
    } catch (e) {
      debugPrint('[DODO][CartSync] deleteItem failed: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      final customerId = await _customerId();
      if (customerId == null) return;
      await _client
          .from('cart_items')
          .delete()
          .eq('customer_id', customerId);
    } catch (e) {
      debugPrint('[DODO][CartSync] clearAll failed: $e');
    }
  }

  Future<List<CartItem>> fetchAll() async {
    try {
      final customerId = await _customerId();
      if (customerId == null) return [];
      final rows = await _client
          .from('cart_items')
          .select('service_id, service_name, image_url, unit_price, quantity')
          .eq('customer_id', customerId);
      return (rows as List<dynamic>)
          .map((r) => CartItem(
                serviceId: r['service_id'] as String,
                serviceName: r['service_name'] as String,
                imageUrl: r['image_url'] as String?,
                unitPrice: (r['unit_price'] as num).toDouble(),
                quantity: r['quantity'] as int,
              ))
          .toList();
    } catch (e) {
      debugPrint('[DODO][CartSync] fetchAll failed: $e');
      return [];
    }
  }
}
