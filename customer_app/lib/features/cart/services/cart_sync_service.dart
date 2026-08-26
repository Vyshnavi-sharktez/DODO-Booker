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
        'parent_node_id': item.parentNodeId,
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
        onConflict: 'customer_id,service_id,parent_node_id',
      );
      debugPrint('[DODO][CartSync][6] upsert response: $response');
    } catch (e) {
      debugPrint('[DODO][CartSync][7] upsertItem EXCEPTION: $e');
      debugPrint('[DODO][CartSync][7] exception type: ${e.runtimeType}');
    }
  }

  Future<void> deleteItem(String serviceId, String? parentNodeId) async {
    try {
      final customerId = await _customerId();
      if (customerId == null) return;
      var query = _client
          .from('cart_items')
          .delete()
          .eq('customer_id', customerId)
          .eq('service_id', serviceId);
      if (parentNodeId != null) {
        query = query.eq('parent_node_id', parentNodeId);
      } else {
        query = query.isFilter('parent_node_id', null);
      }
      await query;
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
          .select('service_id, parent_node_id, service_name, image_url, unit_price, quantity')
          .eq('customer_id', customerId);

      final items = rows as List<dynamic>;
      if (items.isEmpty) return [];

      // Fetch minimum_order_amount for each cart item's catalog node.
      final nodeIds =
          items.map((r) => r['service_id'] as String).toSet().toList();
      final nodeRows = await _client
          .from('catalog_nodes_view')
          .select('id, minimum_order_amount')
          .inFilter('id', nodeIds);
      final minAmtMap = <String, double?>{};
      for (final n in nodeRows as List<dynamic>) {
        final id = n['id'] as String;
        minAmtMap[id] = (n['minimum_order_amount'] as num?)?.toDouble();
      }

      return items
          .map((r) {
            final sid = r['service_id'] as String;
            final pnid = r['parent_node_id'] as String?;
            return CartItem(
              bookingId: '${sid}_${pnid ?? ''}_${DateTime.now().millisecondsSinceEpoch}',
              serviceId: sid,
              parentNodeId: pnid,
              serviceName: r['service_name'] as String,
              imageUrl: r['image_url'] as String?,
              unitPrice: (r['unit_price'] as num).toDouble(),
              quantity: r['quantity'] as int,
              minimumOrderAmount: minAmtMap[sid],
            );
          })
          .toList();
    } catch (e) {
      debugPrint('[DODO][CartSync] fetchAll failed: $e');
      return [];
    }
  }
}
