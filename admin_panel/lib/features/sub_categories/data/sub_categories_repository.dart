import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/sub_category.dart';

class SubCategoriesRepository {
  final SupabaseClient _supabase;

  const SubCategoriesRepository(this._supabase);

  // Sub-category nodes = non-root, non-bookable catalog_nodes.
  // catalog_nodes_view provides is_root_node + parent_ids[] + parent_name.
  // fromMap compatibility: inject 'category_id' and 'categories' keys.

  Future<List<SubCategory>> fetchSubCategories() async {
    final data = await _supabase
        .from('catalog_nodes_view')
        .select()
        .eq('is_root_node', false)
        .eq('is_bookable', false)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((r) => SubCategory.fromMap(_toSubCategoryMap(r as Map<String, dynamic>)))
        .toList();
  }

  Future<SubCategory> createSubCategory({
    required String categoryId,
    required String name,
    required String slug,
    required int sortOrder,
    required bool isActive,
  }) async {
    // 1 — create the node
    final node = await _supabase
        .from('catalog_nodes')
        .insert({
          'name': name,
          'slug': slug,
          'sort_order': sortOrder,
          'is_active': isActive,
          'is_bookable': false,
        })
        .select()
        .single();

    final nodeId = (node as Map<String, dynamic>)['id'] as String;

    // 2 — attach it to the parent category via relationships table
    await _supabase.from('catalog_node_relationships').insert({
      'parent_id': categoryId,
      'child_id': nodeId,
      'sort_order': sortOrder,
    });

    return SubCategory.fromMap({
      ...node,
      'category_id': categoryId,
      'categories': {'id': categoryId, 'name': ''},
    });
  }

  Future<SubCategory> updateSubCategory(
    String id, {
    required String categoryId,
    required String name,
    required String slug,
    required int sortOrder,
    required bool isActive,
  }) async {
    // 1 — update node fields
    final node = await _supabase
        .from('catalog_nodes')
        .update({
          'name': name,
          'slug': slug,
          'sort_order': sortOrder,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();

    // 2 — re-parent if categoryId changed: delete old rels, insert new
    await _supabase
        .from('catalog_node_relationships')
        .delete()
        .eq('child_id', id);

    await _supabase.from('catalog_node_relationships').insert({
      'parent_id': categoryId,
      'child_id': id,
      'sort_order': sortOrder,
    });

    // Fetch updated parent name for the returned model
    final parentRow = await _supabase
        .from('catalog_nodes')
        .select('name')
        .eq('id', categoryId)
        .maybeSingle();
    final parentName = (parentRow as Map<String, dynamic>?)?['name'] as String? ?? '';

    return SubCategory.fromMap({
      ...(node as Map<String, dynamic>),
      'category_id': categoryId,
      'categories': {'id': categoryId, 'name': parentName},
    });
  }

  Future<void> deleteSubCategory(String id) async {
    // Deletes node; cascades to catalog_node_relationships
    await _supabase.from('catalog_nodes').delete().eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('catalog_nodes')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  Future<int> countServices(String subCategoryId) async {
    final data = await _supabase
        .from('catalog_node_relationships')
        .select('child_id')
        .eq('parent_id', subCategoryId);
    return (data as List).length;
  }

  /// Lightweight fetch of active root nodes for the category picker.
  Future<List<({String id, String name})>> fetchCategoryDropdowns() async {
    final data = await _supabase
        .from('catalog_nodes_view')
        .select('id, name')
        .eq('is_root_node', true)
        .eq('is_active', true)
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((r) => (id: r['id'] as String, name: r['name'] as String))
        .toList();
  }

  // Build a map compatible with SubCategory.fromMap from catalog_nodes_view data
  static Map<String, dynamic> _toSubCategoryMap(Map<String, dynamic> row) {
    final parentIds = (row['parent_ids'] as List?)?.cast<String>() ?? [];
    return {
      ...row,
      'category_id': parentIds.isNotEmpty ? parentIds.first : '',
      'categories': {
        'id': parentIds.isNotEmpty ? parentIds.first : '',
        'name': row['parent_name'] ?? '',
      },
    };
  }
}
