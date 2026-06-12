import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wishlist_item_model.dart';

class WishlistService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  static const _wishlistSelect = '''
    *,
    services(
      *,
      sub_categories(
        id, name,
        categories(id, name)
      )
    )
  ''';

  Future<String> _getCustomerId() async {
    final phone = (await SharedPreferences.getInstance()).getString(_phoneKey);
    if (phone == null) throw Exception('Not authenticated');
    final row = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .single();
    final customerId = row['id'] as String;
    debugPrint('[DODO][Wishlist] Customer ID: $customerId');
    return customerId;
  }

  Future<Set<String>> fetchWishlistedIds() async {
    final customerId = await _getCustomerId();
    final data = await _client
        .from('wishlists')
        .select('service_id')
        .eq('customer_id', customerId);
    final rows = data as List;
    return rows.map((e) => e['service_id'] as String).toSet();
  }

  Future<List<WishlistItemModel>> fetchWishlist() async {
    final customerId = await _getCustomerId();
    debugPrint('[DODO][Wishlist] Loading Wishlist for customer_id=$customerId');
    final data = await _client
        .from('wishlists')
        .select(_wishlistSelect)
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    final rows = data as List;
    debugPrint('[DODO][Wishlist] Items Loaded: ${rows.length}');
    return rows
        .map((e) => WishlistItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addToWishlist(String serviceId) async {
    final customerId = await _getCustomerId();
    debugPrint('[DODO][Wishlist] Customer ID: $customerId');
    debugPrint('[DODO][Wishlist] Service ID: $serviceId');
    await _client.from('wishlists').upsert(
      {'customer_id': customerId, 'service_id': serviceId},
      onConflict: 'customer_id,service_id',
    );
    debugPrint('[DODO][Wishlist] Add Success');
  }

  Future<void> removeFromWishlist(String serviceId) async {
    final customerId = await _getCustomerId();
    debugPrint('[DODO][Wishlist] Customer ID: $customerId');
    debugPrint('[DODO][Wishlist] Service ID: $serviceId');
    await _client
        .from('wishlists')
        .delete()
        .eq('customer_id', customerId)
        .eq('service_id', serviceId);
    debugPrint('[DODO][Wishlist] Remove Success');
  }
}
