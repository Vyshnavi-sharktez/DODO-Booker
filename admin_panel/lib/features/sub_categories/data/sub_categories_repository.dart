import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/sub_category.dart';

class SubCategoriesRepository {
  final SupabaseClient _supabase;

  const SubCategoriesRepository(this._supabase);

  Future<List<SubCategory>> fetchSubCategories() async {
    final data = await _supabase
        .from('sub_categories')
        .select('*, categories(id, name)')
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((r) => SubCategory.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<SubCategory> createSubCategory({
    required String categoryId,
    required String name,
    required String slug,
    String? description,
    required int sortOrder,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('sub_categories')
        .insert({
          'category_id': categoryId,
          'name': name,
          'slug': slug,
          if (description != null && description.isNotEmpty)
            'description': description,
          'sort_order': sortOrder,
          'is_active': isActive,
        })
        .select('*, categories(id, name)')
        .single();
    return SubCategory.fromMap(data);
  }

  Future<SubCategory> updateSubCategory(
    String id, {
    required String categoryId,
    required String name,
    required String slug,
    String? description,
    required int sortOrder,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('sub_categories')
        .update({
          'category_id': categoryId,
          'name': name,
          'slug': slug,
          'description': description?.isNotEmpty == true ? description : null,
          'sort_order': sortOrder,
          'is_active': isActive,
        })
        .eq('id', id)
        .select('*, categories(id, name)')
        .single();
    return SubCategory.fromMap(data);
  }

  Future<void> deleteSubCategory(String id) async {
    await _supabase.from('sub_categories').delete().eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('sub_categories')
        .update({'is_active': isActive})
        .eq('id', id);
  }
}
