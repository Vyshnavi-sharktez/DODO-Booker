import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/category.dart';

class CategoriesRepository {
  final SupabaseClient _supabase;

  const CategoriesRepository(this._supabase);

  Future<List<Category>> fetchCategories() async {
    final data = await _supabase
        .from('categories')
        .select()
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
        .from('categories')
        .insert({
          'name': name,
          'slug': slug,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          'sort_order': sortOrder,
          'is_active': isActive,
        })
        .select()
        .single();
    return Category.fromMap(data);
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
        .from('categories')
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
    return Category.fromMap(data);
  }

  Future<void> deleteCategory(String id) async {
    await _supabase.from('categories').delete().eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('categories')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  /// Returns the count of sub-categories and services that belong to [categoryId].
  /// Used to block deletion when dependents exist.
  Future<({int subCategories, int services})> countDependents(
      String categoryId) async {
    final subcatData = await _supabase
        .from('sub_categories')
        .select('id')
        .eq('category_id', categoryId);
    final serviceData = await _supabase
        .from('services')
        .select('id')
        .eq('category_id', categoryId);
    return (
      subCategories: (subcatData as List).length,
      services: (serviceData as List).length,
    );
  }
}
