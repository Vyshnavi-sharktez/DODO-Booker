import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service_availability_area.dart';

class ServiceAvailabilityAreasRepository {
  const ServiceAvailabilityAreasRepository(this._client);
  final SupabaseClient _client;

  Future<List<ServiceAvailabilityArea>> fetchAll() async {
    final rows = await _client
        .from('service_availability_areas')
        .select()
        .order('name');
    return (rows as List<dynamic>)
        .map((r) =>
            ServiceAvailabilityArea.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceAvailabilityArea> create(ServiceAvailabilityArea area) async {
    final row = await _client
        .from('service_availability_areas')
        .insert(area.toInsertMap())
        .select()
        .single();
    return ServiceAvailabilityArea.fromMap(row);
  }

  Future<ServiceAvailabilityArea> update(
      String id, ServiceAvailabilityArea area) async {
    final row = await _client
        .from('service_availability_areas')
        .update({
          ...area.toInsertMap(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return ServiceAvailabilityArea.fromMap(row);
  }

  Future<void> setActive(String id, {required bool active}) async {
    await _client.from('service_availability_areas').update({
      'is_active': active,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('service_availability_areas').delete().eq('id', id);
  }
}
