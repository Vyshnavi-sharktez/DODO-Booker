import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/serving_area.dart';

class ServingAreasDatasource {
  const ServingAreasDatasource(this._client);
  final SupabaseClient _client;

  Future<List<ServingArea>> fetchActive() async {
    final rows = await _client
        .from('vendor_serving_areas')
        .select()
        .eq('is_active', true)
        .order('name');
    return (rows as List<dynamic>)
        .map((r) => ServingArea.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> fetchAssignedIds(String vendorId) async {
    final rows = await _client
        .from('vendor_serving_area_assignments')
        .select('serving_area_id')
        .eq('vendor_id', vendorId);
    return (rows as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)['serving_area_id'] as String)
        .toList();
  }

  Future<void> assign(String vendorId, String areaId) async {
    await _client.from('vendor_serving_area_assignments').upsert(
      {'vendor_id': vendorId, 'serving_area_id': areaId},
      onConflict: 'vendor_id,serving_area_id',
    );
  }

  Future<void> unassign(String vendorId, String areaId) async {
    await _client
        .from('vendor_serving_area_assignments')
        .delete()
        .eq('vendor_id', vendorId)
        .eq('serving_area_id', areaId);
  }

  /// Replaces all assignments for [vendorId] with [areaIds] in two calls.
  Future<void> syncAssignments(String vendorId, List<String> areaIds) async {
    await _client
        .from('vendor_serving_area_assignments')
        .delete()
        .eq('vendor_id', vendorId);
    if (areaIds.isNotEmpty) {
      await _client.from('vendor_serving_area_assignments').insert(
            areaIds
                .map((id) => {'vendor_id': vendorId, 'serving_area_id': id})
                .toList(),
          );
    }
  }
}
