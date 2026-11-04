import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/vendor_root_category.dart';

class VendorRootCategoriesRepository {
  const VendorRootCategoriesRepository(this._client);
  final SupabaseClient _client;

  Future<List<VendorRootCategory>> fetchAll() async {
    final rows = await _client.rpc('admin_get_vendor_categories');
    return (rows as List)
        .map((r) => VendorRootCategory.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<String> create({
    required String name,
    String? iconUrl,
    int sortOrder = 0,
  }) async {
    final id = await _client.rpc('admin_create_vendor_category', params: {
      'p_name': name,
      'p_icon_url': iconUrl,
      'p_sort_order': sortOrder,
    });
    return id as String;
  }

  Future<void> update({
    required String id,
    required String name,
    String? iconUrl,
    int sortOrder = 0,
  }) async {
    await _client.rpc('admin_update_vendor_category', params: {
      'p_id': id,
      'p_name': name,
      'p_icon_url': iconUrl,
      'p_sort_order': sortOrder,
    });
  }

  Future<CategoryDeps> checkDeps(String id) async {
    final rows = await _client.rpc(
      'admin_check_vendor_category_deps',
      params: {'p_id': id},
    );
    final row = Map<String, dynamic>.from((rows as List).first as Map);
    return CategoryDeps(
      activeServiceCount: (row['active_service_count'] as int?) ?? 0,
      totalServiceCount: (row['total_service_count'] as int?) ?? 0,
      vendorCount: (row['vendor_count'] as int?) ?? 0,
    );
  }

  Future<int> reassign({
    required String fromId,
    required String toId,
  }) async {
    final count = await _client.rpc('admin_reassign_vendor_category', params: {
      'p_from_id': fromId,
      'p_to_id': toId,
    });
    return (count as int?) ?? 0;
  }

  Future<void> delete(String id) async {
    await _client.rpc('admin_delete_vendor_category', params: {'p_id': id});
  }
}

class CategoryDeps {
  const CategoryDeps({
    required this.activeServiceCount,
    required this.totalServiceCount,
    required this.vendorCount,
  });
  final int activeServiceCount;
  final int totalServiceCount;
  final int vendorCount;

  bool get hasDependencies => totalServiceCount > 0;
}
