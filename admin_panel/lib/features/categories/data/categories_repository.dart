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
    String? icon,
    String? imageUrl,
    String? description,
    required int sortOrder,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('categories')
        .insert({
          'name': name,
          'slug': slug,
          if (icon != null && icon.isNotEmpty) 'icon': icon,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          if (description != null && description.isNotEmpty)
            'description': description,
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
    String? icon,
    String? imageUrl,
    String? description,
    required int sortOrder,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('categories')
        .update({
          'name': name,
          'slug': slug,
          'icon': icon?.isNotEmpty == true ? icon : null,
          'image_url': imageUrl?.isNotEmpty == true ? imageUrl : null,
          'description': description?.isNotEmpty == true ? description : null,
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
}
