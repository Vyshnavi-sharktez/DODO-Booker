import 'package:supabase_flutter/supabase_flutter.dart';

class ServicesRemoteDatasource {
  const ServicesRemoteDatasource(this._client);
  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> fetchVendorServices(
    String vendorId,
  ) async {
    // Step 1 — get vendor_services rows
    final vsData = await _client
        .from('vendor_services')
        .select('id, vendor_id, service_id, is_active, custom_price, created_at')
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(vsData as List);
    if (rows.isEmpty) return rows;

    // Step 2 — fetch catalog_node data for the service IDs
    // service_id == catalog_node.id (UUIDs preserved during Phase 1 migration)
    final serviceIds =
        rows.map((r) => r['service_id'] as String).toSet().toList();

    final nodeData = await _client
        .from('catalog_nodes_view')
        .select('id, name, base_price, estimated_duration, parent_name')
        .inFilter('id', serviceIds);

    final nodesById = <String, Map<String, dynamic>>{
      for (final n in (nodeData as List))
        (n as Map<String, dynamic>)['id'] as String: n,
    };

    // Build output with the same nested map shape the upper layers expect
    return rows.map((row) {
      final node = nodesById[row['service_id'] as String] ?? const {};
      return {
        ...row,
        'services': {
          'id': node['id'],
          'name': node['name'],
          'base_price': node['base_price'],
          'estimated_duration': node['estimated_duration'],
          'categories': {'id': null, 'name': node['parent_name']},
          'sub_categories': {'id': null, 'name': node['parent_name']},
        },
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchCatalogServices() async {
    final data = await _client
        .from('catalog_nodes_view')
        .select('id, name, base_price, estimated_duration, parent_name')
        .eq('is_active', true)
        .eq('is_bookable', true)
        .order('name');

    // Return with the same shape the upper layers expect for a "services" row
    return (data as List).map((e) {
      final r = e as Map<String, dynamic>;
      return {
        'id': r['id'],
        'name': r['name'],
        'base_price': r['base_price'],
        'estimated_duration': r['estimated_duration'],
        'categories': {'id': null, 'name': r['parent_name']},
        'sub_categories': {'id': null, 'name': r['parent_name']},
      };
    }).toList().cast<Map<String, dynamic>>();
  }

  Future<void> assignServices(
    String vendorId,
    List<String> serviceIds,
  ) async {
    await _client.from('vendor_services').insert(
          serviceIds
              .map(
                (id) => {
                  'vendor_id': vendorId,
                  'service_id': id,
                  'is_active': true,
                },
              )
              .toList(),
        );
  }

  Future<void> toggleService(String vendorServiceId, bool isActive) async {
    await _client
        .from('vendor_services')
        .update({'is_active': isActive})
        .eq('id', vendorServiceId);
  }
}
