import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service.dart';

class ServicesRepository {
  final SupabaseClient _supabase;

  const ServicesRepository(this._supabase);

  // Service nodes = bookable catalog_nodes (is_bookable = true).
  // Service UUID == catalog_node.id (preserved during Phase 1 migration).
  // catalog_nodes_view provides parent_ids[] and parent_name.
  // fromMap compatibility: inject sub_category_id, sub_categories, categories.

  Future<List<Service>> fetchServices() async {
    final data = await _supabase
        .from('catalog_nodes_view')
        .select()
        .eq('is_bookable', true)
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((r) => Service.fromMap(_toServiceMap(r as Map<String, dynamic>)))
        .toList();
  }

  Future<Service> createService({
    required String categoryId,
    required String subCategoryId,
    required String name,
    required String slug,
    required double basePrice,
    required int estimatedDuration,
    String? imageUrl,
    required bool isActive,
  }) async {
    // 1 — create the catalog_node as a bookable service
    final node = await _supabase
        .from('catalog_nodes')
        .insert({
          'name': name,
          'slug': slug,
          'base_price': basePrice,
          'estimated_duration': estimatedDuration,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          'is_active': isActive,
          'is_bookable': true,
        })
        .select()
        .single();

    final nodeId = (node as Map<String, dynamic>)['id'] as String;

    // 2 — attach to subcategory (parent) via relationships
    await _supabase.from('catalog_node_relationships').insert({
      'parent_id': subCategoryId,
      'child_id': nodeId,
      'sort_order': 0,
    });

    // Resolve subcategory and category names for the returned model
    final parentNames = await _resolveParentNames(subCategoryId, categoryId);

    return Service.fromMap({
      ...node,
      'sub_category_id': subCategoryId,
      'sub_categories': {'id': subCategoryId, 'name': parentNames.$1},
      'category_id': categoryId,
      'categories': {'id': categoryId, 'name': parentNames.$2},
    });
  }

  Future<Service> updateService(
    String id, {
    required String categoryId,
    required String subCategoryId,
    required String name,
    required String slug,
    required double basePrice,
    required int estimatedDuration,
    String? imageUrl,
    required bool isActive,
  }) async {
    // 1 — update catalog_node fields
    final node = await _supabase
        .from('catalog_nodes')
        .update({
          'name': name,
          'slug': slug,
          'base_price': basePrice,
          'estimated_duration': estimatedDuration,
          'image_url': imageUrl?.isNotEmpty == true ? imageUrl : null,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();

    // 2 — re-parent if subcategory changed
    await _supabase
        .from('catalog_node_relationships')
        .delete()
        .eq('child_id', id);

    await _supabase.from('catalog_node_relationships').insert({
      'parent_id': subCategoryId,
      'child_id': id,
      'sort_order': 0,
    });

    final parentNames = await _resolveParentNames(subCategoryId, categoryId);

    return Service.fromMap({
      ...(node as Map<String, dynamic>),
      'sub_category_id': subCategoryId,
      'sub_categories': {'id': subCategoryId, 'name': parentNames.$1},
      'category_id': categoryId,
      'categories': {'id': categoryId, 'name': parentNames.$2},
    });
  }

  Future<void> deleteService(String id) async {
    await _supabase.from('catalog_nodes').delete().eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('catalog_nodes')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  Future<int> countAttributes(String serviceId) async {
    final data = await _supabase
        .from('service_attributes')
        .select('id')
        .eq('service_id', serviceId);
    return (data as List).length;
  }

  /// Lightweight fetch of subcategory nodes (non-root, non-bookable) with their
  /// parent category info — used for the subcategory picker in the services form.
  Future<
      List<
          ({
            String id,
            String name,
            String categoryId,
            String categoryName
          })>> fetchSubCategoryDropdowns() async {
    final data = await _supabase
        .from('catalog_nodes_view')
        .select()
        .eq('is_root_node', false)
        .eq('is_bookable', false)
        .eq('is_active', true)
        .order('name', ascending: true);

    return (data as List<dynamic>).map((r) {
      final row = r as Map<String, dynamic>;
      final parentIds = (row['parent_ids'] as List?)?.cast<String>() ?? [];
      return (
        id: row['id'] as String,
        name: row['name'] as String,
        categoryId: parentIds.isNotEmpty ? parentIds.first : '',
        categoryName: (row['parent_name'] as String?) ?? '',
      );
    }).toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Fetches name for [subCategoryId] and [categoryId] in parallel.
  Future<(String, String)> _resolveParentNames(
    String subCategoryId,
    String categoryId,
  ) async {
    final results = await Future.wait([
      _supabase
          .from('catalog_nodes')
          .select('name')
          .eq('id', subCategoryId)
          .maybeSingle(),
      _supabase
          .from('catalog_nodes')
          .select('name')
          .eq('id', categoryId)
          .maybeSingle(),
    ]);
    final subName =
        (results[0] as Map<String, dynamic>?)?['name'] as String? ?? '';
    final catName =
        (results[1] as Map<String, dynamic>?)?['name'] as String? ?? '';
    return (subName, catName);
  }

  /// Maps catalog_nodes_view row to a Service.fromMap-compatible map.
  static Map<String, dynamic> _toServiceMap(Map<String, dynamic> row) {
    final parentIds = (row['parent_ids'] as List?)?.cast<String>() ?? [];
    return {
      ...row,
      'sub_category_id': parentIds.isNotEmpty ? parentIds.first : '',
      'sub_categories': {
        'id': parentIds.isNotEmpty ? parentIds.first : '',
        'name': row['parent_name'] ?? '',
      },
      // Category (grandparent) is not available in single-level view;
      // would require an extra query. Admin CatalogV2 shows full tree.
      'category_id': '',
      'categories': {'id': '', 'name': ''},
    };
  }
}
