import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service_addon.dart';

class ServiceAddonsRepository {
  final SupabaseClient _supabase;

  const ServiceAddonsRepository(this._supabase);

  Future<List<ServiceAddon>> fetchByService(String serviceId) async {
    final data = await _supabase
        .from('addons')
        .select()
        .eq('service_id', serviceId)
        .order('created_at', ascending: true);
    return (data as List<dynamic>)
        .map((r) => ServiceAddon.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceAddon> create({
    required String serviceId,
    required String name,
    String? description,
    required double price,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('addons')
        .insert({
          'service_id': serviceId,
          'name': name,
          if (description != null && description.isNotEmpty)
            'description': description,
          'price': price,
          'is_active': isActive,
        })
        .select()
        .single();
    return ServiceAddon.fromMap(data);
  }

  Future<ServiceAddon> update(
    String id, {
    required String name,
    String? description,
    required double price,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('addons')
        .update({
          'name': name,
          'description': description,
          'price': price,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return ServiceAddon.fromMap(data);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('addons')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  Future<void> delete(String id) async {
    await _supabase.from('addons').delete().eq('id', id);
  }
}
