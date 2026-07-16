import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/vendor_serving_area.dart';

class VendorServingAreasRepository {
  const VendorServingAreasRepository(this._client);
  final SupabaseClient _client;

  Future<List<VendorServingArea>> fetchAll() async {
    final rows = await _client
        .from('vendor_serving_areas')
        .select()
        .order('name');
    return (rows as List<dynamic>)
        .map((r) => VendorServingArea.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<VendorServingArea> create(VendorServingArea area) async {
    final row = await _client
        .from('vendor_serving_areas')
        .insert(area.toInsertMap())
        .select()
        .single();
    return VendorServingArea.fromMap(row);
  }

  Future<VendorServingArea> update(String id, VendorServingArea area) async {
    final row = await _client
        .from('vendor_serving_areas')
        .update({
          ...area.toInsertMap(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return VendorServingArea.fromMap(row);
  }

  Future<void> setActive(String id, {required bool active}) async {
    await _client
        .from('vendor_serving_areas')
        .update({'is_active': active, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  /// Returns true if deleted, false if blocked by existing vendor assignments.
  Future<({bool deleted, String? error})> delete(String id) async {
    try {
      await _client.from('vendor_serving_areas').delete().eq('id', id);
      return (deleted: true, error: null);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('vendor_serving_area_assignments') ||
          msg.contains('foreign') ||
          msg.contains('restrict')) {
        return (
          deleted: false,
          error: 'This area is assigned to one or more vendors. '
              'Remove all vendor assignments before deleting.',
        );
      }
      return (deleted: false, error: msg);
    }
  }

  /// Fetches the IDs of serving areas assigned to [vendorId].
  Future<List<String>> fetchAssignedAreaIds(String vendorId) async {
    final rows = await _client
        .from('vendor_serving_area_assignments')
        .select('serving_area_id')
        .eq('vendor_id', vendorId);
    return (rows as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)['serving_area_id'] as String)
        .toList();
  }

  /// Replaces a vendor's assigned areas with [newAreaIds].
  Future<void> syncVendorAssignments(
    String vendorId,
    List<String> newAreaIds,
  ) async {
    await _client
        .from('vendor_serving_area_assignments')
        .delete()
        .eq('vendor_id', vendorId);

    if (newAreaIds.isNotEmpty) {
      await _client.from('vendor_serving_area_assignments').insert(
            newAreaIds
                .map((areaId) => {
                      'vendor_id': vendorId,
                      'serving_area_id': areaId,
                    })
                .toList(),
          );
    }
  }

  /// Counts how many vendors are assigned to the given area.
  Future<int> countAssignments(String areaId) async {
    final res = await _client
        .from('vendor_serving_area_assignments')
        .select()
        .eq('serving_area_id', areaId)
        .count(CountOption.exact);
    return res.count;
  }

  /// Returns a map of {serving_area_id → vendor_count} for all areas.
  /// Single query, no N+1.
  Future<Map<String, int>> fetchAllAssignmentCounts() async {
    final rows = await _client
        .from('vendor_serving_area_assignments')
        .select('serving_area_id');
    final map = <String, int>{};
    for (final r in rows as List<dynamic>) {
      final id = (r as Map<String, dynamic>)['serving_area_id'] as String;
      map[id] = (map[id] ?? 0) + 1;
    }
    return map;
  }

  /// Returns vendor summaries assigned to a specific area via a join.
  Future<List<Map<String, dynamic>>> fetchVendorsForArea(String areaId) async {
    final rows = await _client
        .from('vendor_serving_area_assignments')
        .select(
          'vendors!vendor_id(id, business_name, owner_name, phone, status, is_active)',
        )
        .eq('serving_area_id', areaId);
    return (rows as List<dynamic>)
        .map((r) =>
            (r as Map<String, dynamic>)['vendors'] as Map<String, dynamic>)
        .toList();
  }

  /// Returns `{serving_area_id → Set(vendor_id)}` for every assignment row.
  Future<Map<String, Set<String>>> fetchAllAssignments() async {
    final rows = await _client
        .from('vendor_serving_area_assignments')
        .select('serving_area_id, vendor_id');
    final map = <String, Set<String>>{};
    for (final r in rows as List<dynamic>) {
      final m = r as Map<String, dynamic>;
      final areaId = m['serving_area_id'] as String;
      final vendorId = m['vendor_id'] as String;
      (map[areaId] ??= {}).add(vendorId);
    }
    return map;
  }

  /// Returns full VendorServingArea objects assigned to a vendor via a join.
  Future<List<VendorServingArea>> fetchAssignedAreasForVendor(
      String vendorId) async {
    final rows = await _client
        .from('vendor_serving_area_assignments')
        .select('vendor_serving_areas!serving_area_id(*)')
        .eq('vendor_id', vendorId);
    return (rows as List<dynamic>)
        .map((r) => VendorServingArea.fromMap(
            (r as Map<String, dynamic>)['vendor_serving_areas']
                as Map<String, dynamic>))
        .toList();
  }
}
