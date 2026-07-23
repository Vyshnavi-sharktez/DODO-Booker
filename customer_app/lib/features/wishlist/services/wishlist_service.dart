import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wishlist_item_model.dart';

class WishlistService {
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

    // Step 1: fetch wishlist rows without any join.
    // The catalog_nodes(*) embed was broken because wishlists.node_id is NULL
    // for items inserted via addToWishlist() before this fix; PostgREST returns
    // null for the embed on those rows, crashing WishlistItemModel.fromJson().
    final wishlistRows = (await _client
        .from('wishlists')
        .select('id, customer_id, service_id, node_id, created_at')
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)) as List;

    debugPrint('[DODO][Wishlist] Wishlist rows: ${wishlistRows.length}');
    if (wishlistRows.isEmpty) return [];

    // Step 2: resolve node IDs.
    // node_id = service_id for all rows (service UUIDs preserved as catalog_node
    // IDs in the Catalog V2 migration). Fall back to service_id when node_id is
    // null (items added before addToWishlist() was fixed to include node_id).
    final nodeIds = wishlistRows
        .map((r) => ((r as Map)['node_id'] ?? r['service_id']) as String)
        .toList();

    final nodeRows = (await _client
        .from('catalog_nodes_view')
        .select()
        .inFilter('id', nodeIds)) as List;

    final nodeMap = <String, Map<String, dynamic>>{
      for (final n in nodeRows)
        (n as Map<String, dynamic>)['id'] as String: n,
    };

    debugPrint('[DODO][Wishlist] Catalog nodes resolved: ${nodeMap.length}');

    return wishlistRows
        .where((r) {
          final id = ((r as Map)['node_id'] ?? r['service_id']) as String;
          return nodeMap.containsKey(id);
        })
        .map((r) {
          final row = r as Map<String, dynamic>;
          final id = (row['node_id'] ?? row['service_id']) as String;
          return WishlistItemModel.fromNodeMap(
            id: row['id'] as String,
            customerId: row['customer_id'] as String,
            serviceId: id,
            createdAt: DateTime.parse(row['created_at'] as String),
            nodeData: nodeMap[id]!,
          );
        })
        .toList();
  }

  Future<void> addToWishlist(String serviceId) async {
    final customerId = await _getCustomerId();
    debugPrint('[DODO][Wishlist] Customer ID: $customerId');
    debugPrint('[DODO][Wishlist] Service ID: $serviceId');
    await _client.from('wishlists').upsert(
      {
        'customer_id': customerId,
        'service_id': serviceId,
        // node_id mirrors service_id: service UUIDs were preserved as
        // catalog_node IDs in the Catalog V2 migration (migration step 4c).
        'node_id': serviceId,
      },
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
