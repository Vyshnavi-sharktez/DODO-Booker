import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service.dart';

class ServicesRepository {
  final SupabaseClient _supabase;

  const ServicesRepository(this._supabase);

  Future<List<Service>> fetchServices() async {
    final data = await _supabase
        .from('services')
        .select('*, categories(id, name), sub_categories(id, name)')
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((r) => Service.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<Service> createService({
    required String categoryId,
    required String subCategoryId,
    required String name,
    required String slug,
    String? description,
    required double basePrice,
    required int estimatedDuration,
    String? imageUrl,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('services')
        .insert({
          'category_id': categoryId,
          'sub_category_id': subCategoryId,
          'name': name,
          'slug': slug,
          if (description != null && description.isNotEmpty)
            'description': description,
          'base_price': basePrice,
          'estimated_duration': estimatedDuration,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          'is_active': isActive,
        })
        .select('*, categories(id, name), sub_categories(id, name)')
        .single();
    return Service.fromMap(data);
  }

  Future<Service> updateService(
    String id, {
    required String categoryId,
    required String subCategoryId,
    required String name,
    required String slug,
    String? description,
    required double basePrice,
    required int estimatedDuration,
    String? imageUrl,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('services')
        .update({
          'category_id': categoryId,
          'sub_category_id': subCategoryId,
          'name': name,
          'slug': slug,
          'description': description?.isNotEmpty == true ? description : null,
          'base_price': basePrice,
          'estimated_duration': estimatedDuration,
          'image_url': imageUrl?.isNotEmpty == true ? imageUrl : null,
          'is_active': isActive,
        })
        .eq('id', id)
        .select('*, categories(id, name), sub_categories(id, name)')
        .single();
    return Service.fromMap(data);
  }

  Future<void> deleteService(String id) async {
    await _supabase.from('services').delete().eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('services')
        .update({'is_active': isActive})
        .eq('id', id);
  }
}
