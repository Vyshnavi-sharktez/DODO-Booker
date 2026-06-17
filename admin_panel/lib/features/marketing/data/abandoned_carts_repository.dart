import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AbandonedCartItem {
  final String serviceName;
  final int quantity;
  final double unitPrice;

  const AbandonedCartItem({
    required this.serviceName,
    required this.quantity,
    required this.unitPrice,
  });

  double get totalPrice => unitPrice * quantity;
}

class AbandonedCart {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final int itemCount;
  final double cartValue;
  final DateTime lastUpdated;
  final List<AbandonedCartItem> items;

  const AbandonedCart({
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.itemCount,
    required this.cartValue,
    required this.lastUpdated,
    required this.items,
  });

  Duration get cartAge => DateTime.now().difference(lastUpdated);

  String get cartAgeLabel {
    final h = cartAge.inHours;
    final d = cartAge.inDays;
    if (d >= 1) return '${d}d ago';
    return '${h}h ago';
  }
}

class AbandonedCartsRepository {
  final SupabaseClient _supabase;

  const AbandonedCartsRepository(this._supabase);

  /// Customers whose entire cart (max updated_at) is older than 6 hours.
  Future<List<AbandonedCart>> getAbandonedCarts() async {
    final data = await _supabase
        .from('cart_items')
        .select(
          'customer_id, service_name, unit_price, quantity, updated_at,'
          'customers(id, full_name, phone)',
        )
        .order('updated_at', ascending: false);

    debugPrint('[DODO][AbandonedCarts] total cart_items rows fetched: ${(data as List).length}');

    // Group rows by customer_id
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final Map<String, Map<String, dynamic>> customerMeta = {};

    for (final row in (data as List<dynamic>)) {
      final r = row as Map<String, dynamic>;
      final customerId = r['customer_id'] as String;
      grouped.putIfAbsent(customerId, () => []).add(r);
      customerMeta.putIfAbsent(
        customerId,
        () => r['customers'] as Map<String, dynamic>? ?? {},
      );
    }

    final cutoff = DateTime.now().subtract(const Duration(hours: 6));
    final result = <AbandonedCart>[];

    for (final entry in grouped.entries) {
      final customerId = entry.key;
      final rows = entry.value;

      // Only include if the most recently updated item is still older than cutoff
      final maxUpdated = rows
          .map((r) => DateTime.parse(r['updated_at'] as String).toLocal())
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (!maxUpdated.isBefore(cutoff)) continue;

      final customer = customerMeta[customerId]!;
      final itemCount =
          rows.fold<int>(0, (sum, r) => sum + (r['quantity'] as int));
      final cartValue = rows.fold<double>(
        0.0,
        (sum, r) =>
            sum + (r['unit_price'] as num).toDouble() * (r['quantity'] as int),
      );

      result.add(AbandonedCart(
        customerId: customerId,
        customerName: customer['full_name'] as String? ?? '',
        customerPhone: customer['phone'] as String? ?? '',
        itemCount: itemCount,
        cartValue: cartValue,
        lastUpdated: maxUpdated,
        items: rows
            .map((r) => AbandonedCartItem(
                  serviceName: r['service_name'] as String? ?? '',
                  quantity: r['quantity'] as int,
                  unitPrice: (r['unit_price'] as num).toDouble(),
                ))
            .toList(),
      ));
    }

    result.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    debugPrint('[DODO][AbandonedCarts] cutoff: $cutoff');
    debugPrint('[DODO][AbandonedCarts] abandoned carts returned: ${result.length}');
    return result;
  }

  /// Sends a cart-reminder notification to the customer.
  Future<void> sendCartReminder(
    String customerId,
    String customerName,
  ) async {
    final displayName = customerName.isNotEmpty ? customerName : 'there';
    await _supabase.from('notifications').insert({
      'user_type': 'customer',
      'user_id': customerId,
      'title': 'Your cart is waiting',
      'message':
          'Hi $displayName, you left some items in your cart. Book now and get your home services done!',
      'notification_type': 'cart_reminder',
      'is_read': false,
    });
    debugPrint('[DODO][Marketing] Cart reminder sent to customer=$customerId');
  }
}
