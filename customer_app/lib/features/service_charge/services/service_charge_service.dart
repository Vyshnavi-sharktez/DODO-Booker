import 'package:supabase_flutter/supabase_flutter.dart';

import '../../cart/models/cart_item.dart';

class ServiceChargeService {
  final _client = Supabase.instance.client;

  /// Calls the server-side RPC to resolve the total service charge for [items].
  /// Only DODO catalog items with a known parentNodeId are eligible.
  /// Returns the server-computed total (never trusts client math).
  Future<double> resolveCartServiceCharge(List<CartItem> items) async {
    try {
      final cartItems = items
          .where((i) => !i.isCustomService && !i.isAmc && i.parentNodeId != null)
          .map((i) => {
                'service_id': i.serviceId,
                'parent_node_id': i.parentNodeId,
              })
          .toList();
      if (cartItems.isEmpty) return 0;
      final result = await _client.rpc(
        'resolve_service_charge_for_cart',
        params: {'p_cart_items': cartItems},
      );
      if (result is Map) return (result['total'] as num?)?.toDouble() ?? 0;
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
