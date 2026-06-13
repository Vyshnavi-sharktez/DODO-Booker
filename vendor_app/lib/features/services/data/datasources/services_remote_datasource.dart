import 'package:supabase_flutter/supabase_flutter.dart';

class ServicesRemoteDatasource {
  const ServicesRemoteDatasource(this._client);
  final SupabaseClient _client;

  static const _vendorServicesSelect =
      'id, vendor_id, service_id, is_active, custom_price, created_at, '
      'services(id, name, base_price, estimated_duration, '
      'categories(id, name), sub_categories(id, name))';

  static const _catalogSelect =
      'id, name, base_price, estimated_duration, '
      'categories(id, name), sub_categories(id, name)';

  Future<List<Map<String, dynamic>>> fetchVendorServices(
    String vendorId,
  ) async {
    final data = await _client
        .from('vendor_services')
        .select(_vendorServicesSelect)
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> fetchCatalogServices() async {
    final data = await _client
        .from('services')
        .select(_catalogSelect)
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(data as List);
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
