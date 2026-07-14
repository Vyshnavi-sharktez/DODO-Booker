import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/category.dart';

class CategoriesRepository {
  final SupabaseClient _supabase;

  const CategoriesRepository(this._supabase);

  // Category nodes = root catalog_nodes (no parent in catalog_node_relationships).
  // catalog_nodes_view computes is_root_node for this filter.
  // Writes go directly to catalog_nodes (no relationship row needed for roots).

  Future<List<Category>> fetchCategories() async {
    final data = await _supabase
        .from('catalog_nodes_view')
        .select()
        .eq('is_root_node', true)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((r) => Category.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<Category> createCategory({
    required String name,
    required String slug,
    String? imageUrl,
    required int sortOrder,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('catalog_nodes')
        .insert({
          'name': name,
          'slug': slug,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          'sort_order': sortOrder,
          'is_active': isActive,
          'is_bookable': false,
        })
        .select()
        .single();
    // No relationship row → view computes is_root_node = true
    return Category.fromMap(data as Map<String, dynamic>);
  }

  Future<Category> updateCategory(
    String id, {
    required String name,
    required String slug,
    String? imageUrl,
    required int sortOrder,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('catalog_nodes')
        .update({
          'name': name,
          'slug': slug,
          'image_url': imageUrl?.isNotEmpty == true ? imageUrl : null,
          'sort_order': sortOrder,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return Category.fromMap(data as Map<String, dynamic>);
  }

  Future<void> deleteCategory(String id) async {
    // Deleting the node cascades to catalog_node_relationships.
    await _supabase.from('catalog_nodes').delete().eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('catalog_nodes')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  /// Returns the count of sub-categories (direct children) and services
  /// (bookable grandchildren) that belong to [categoryId].
  Future<({int subCategories, int services})> countDependents(
      String categoryId) async {
    // Direct children = subcategory nodes
    final childRels = await _supabase
        .from('catalog_node_relationships')
        .select('child_id')
        .eq('parent_id', categoryId);

    final childIds = (childRels as List)
        .map((r) => r['child_id'] as String)
        .toList();

    if (childIds.isEmpty) {
      return (subCategories: 0, services: 0);
    }

    // Grandchildren (services) whose parent is one of those children
    final grandchildRels = await _supabase
        .from('catalog_node_relationships')
        .select('child_id')
        .inFilter('parent_id', childIds);

    return (
      subCategories: childIds.length,
      services: (grandchildRels as List).length,
    );
  }
}
