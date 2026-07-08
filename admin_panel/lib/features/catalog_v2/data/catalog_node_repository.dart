import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/catalog_node.dart';

class CatalogNodeRepository {
  final SupabaseClient _supabase;

  const CatalogNodeRepository(this._supabase);

  /// Fetches ALL nodes (active and inactive) from the view.
  /// The admin's authenticated RLS policy allows unrestricted reads.
  /// The view adds children_count (active children) + parent_name/slug.
  Future<List<CatalogNode>> fetchAll() async {
    final data = await _supabase
        .from('catalog_nodes_view')
        .select()
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((r) => CatalogNode.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<CatalogNode> createNode({
    String? parentId,
    required String name,
    required String slug,
    String? description,
    String? imageUrl,
    String? iconKey,
    required int sortOrder,
    required bool isActive,
    required bool isBookable,
    double? basePrice,
    int? estimatedDuration,
  }) async {
    final data = await _supabase
        .from('catalog_nodes')
        .insert({
          if (parentId != null) 'parent_id': parentId,
          'name': name,
          'slug': slug,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          if (iconKey != null && iconKey.isNotEmpty) 'icon_key': iconKey,
          'sort_order': sortOrder,
          'is_active': isActive,
          'is_bookable': isBookable,
          if (basePrice != null) 'base_price': basePrice,
          if (estimatedDuration != null)
            'estimated_duration': estimatedDuration,
        })
        .select()
        .single();
    // Refetch via view to get children_count + parent_name
    return _fetchById(data['id'] as String);
  }

  Future<CatalogNode> updateNode(
    String id, {
    String? parentId,
    required String name,
    required String slug,
    String? description,
    String? imageUrl,
    String? iconKey,
    required int sortOrder,
    required bool isActive,
    required bool isBookable,
    double? basePrice,
    int? estimatedDuration,
  }) async {
    await _supabase
        .from('catalog_nodes')
        .update({
          'parent_id': parentId,
          'name': name,
          'slug': slug,
          'description':
              description?.isNotEmpty == true ? description : null,
          'image_url': imageUrl?.isNotEmpty == true ? imageUrl : null,
          'icon_key': iconKey?.isNotEmpty == true ? iconKey : null,
          'sort_order': sortOrder,
          'is_active': isActive,
          'is_bookable': isBookable,
          'base_price': basePrice,
          'estimated_duration': estimatedDuration,
        })
        .eq('id', id);
    return _fetchById(id);
  }

  /// Deletes a node. Supabase will raise a foreign-key error (ON DELETE
  /// RESTRICT) if the node still has children — the caller must handle it.
  Future<void> deleteNode(String id) async {
    await _supabase.from('catalog_nodes').delete().eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('catalog_nodes')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  /// Sets is_bookable on the node. This is an explicit admin action — the
  /// system never changes is_bookable automatically.
  Future<void> toggleBookable(String id, {required bool isBookable}) async {
    await _supabase
        .from('catalog_nodes')
        .update({'is_bookable': isBookable})
        .eq('id', id);
  }

  /// Moves [id] to a new parent. Pass [newParentId] = null to make it a root.
  /// The DB trigger trg_catalog_nodes_no_cycle rejects any move that would
  /// create a circular reference, so the caller only needs to handle the
  /// exception message for display.
  Future<void> moveNode(String id, String? newParentId) async {
    await _supabase
        .from('catalog_nodes')
        .update({'parent_id': newParentId})
        .eq('id', id);
  }

  /// Returns the count of direct children (all, not just active).
  /// Used to block deletion when children exist.
  Future<int> countChildren(String id) async {
    final data = await _supabase
        .from('catalog_nodes')
        .select('id')
        .eq('parent_id', id);
    return (data as List).length;
  }

  Future<CatalogNode> _fetchById(String id) async {
    final data = await _supabase
        .from('catalog_nodes_view')
        .select()
        .eq('id', id)
        .single();
    return CatalogNode.fromMap(data);
  }
}
