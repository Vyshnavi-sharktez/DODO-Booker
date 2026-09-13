import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class ServicesRemoteDatasource {
  const ServicesRemoteDatasource(this._client);
  final SupabaseClient _client;

  /// Fetches the vendor's assigned services joined with their full catalog entry.
  ///
  /// Step 1 — vendor_services rows for this vendor.
  /// Step 2 — full catalog_nodes_view rows for those service IDs (same query
  ///           the Admin panel uses: .select() with no column restriction).
  /// Step 3 — merge: each vendor row gets a 'catalog' key holding the raw
  ///           view row so AssignedService.fromMap can read it directly.
  Future<List<Map<String, dynamic>>> fetchVendorServices(
    String vendorId,
  ) async {
    final vsData = await _client
        .from('vendor_services')
        .select('id, vendor_id, service_id, is_active, created_at')
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(vsData as List);
    if (rows.isEmpty) return rows;

    final serviceIds =
        rows.map((r) => r['service_id'] as String).toSet().toList();

    final nodeData = await _client
        .from('catalog_nodes_view')
        .select()
        .inFilter('id', serviceIds);

    final nodesById = <String, Map<String, dynamic>>{
      for (final n in (nodeData as List))
        (n as Map<String, dynamic>)['id'] as String: n,
    };

    return rows.map((row) {
      final node = nodesById[row['service_id'] as String] ??
          const <String, dynamic>{};
      return {...row, 'catalog': node};
    }).toList();
  }

  /// All active catalog nodes a vendor can register against:
  ///   • is_bookable = true  — specific bookable leaf services
  ///   • is_bookable = false AND children_count > 0  — parent/category nodes
  ///     that cover all bookable descendants when registered
  ///
  /// Non-bookable nodes with no active children are excluded (nothing to cover).
  Future<List<Map<String, dynamic>>> fetchCatalogServices() async {
    final data = await _client
        .from('catalog_nodes_view')
        .select()
        .eq('is_active', true)
        .or('is_bookable.eq.true,children_count.gt.0')
        .order('sort_order', ascending: true)
        .order('name');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Returns ALL active catalog nodes (bookable or not) with [name] and
  /// [parent_name]. Fetching bookable nodes too ensures dual-role nodes (e.g.
  /// "EV Repair", "Refrigerator Services" — bookable AND parents of other
  /// bookable nodes) appear in the parentOf map and resolve to the correct root.
  Future<List<Map<String, dynamic>>> fetchCatalogTree() async {
    final data = await _client
        .from('catalog_nodes_view')
        .select('name, parent_name')
        .eq('is_active', true);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Top-8 active, bookable services for the search trending section.
  Future<List<Map<String, dynamic>>> fetchTrendingServices() async {
    final data = await _client
        .from('catalog_nodes_view')
        .select()
        .eq('is_active', true)
        .eq('is_bookable', true)
        .order('sort_order', ascending: true)
        .order('name')
        .limit(8);
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

  Future<void> removeVendorService(String vendorServiceId) async {
    await _client
        .from('vendor_services')
        .delete()
        .eq('id', vendorServiceId);
  }

  Future<List<Map<String, dynamic>>> fetchMyServiceRequests(
    String vendorId,
  ) async {
    final data = await _client
        .from('vendor_service_requests')
        .select(
          'id, service_name, description, price, active_price, new_price, '
          'image_url, status, rejection_reason, request_type, '
          'parent_request_id, is_active, created_at',
        )
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<Map<String, dynamic>?> fetchServiceRequestById(String requestId) async {
    return await _client
        .from('vendor_service_requests')
        .select('id, service_name, description, price, image_url, status, rejection_reason, created_at')
        .eq('id', requestId)
        .maybeSingle();
  }

  Future<String?> uploadServiceRequestImage({
    required String vendorId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final path =
        '$vendorId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('vendor-requests').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return _client.storage.from('vendor-requests').getPublicUrl(path);
  }

  Future<String> submitServiceRequest({
    required String vendorId,
    required String serviceName,
    String? description,
    double? price,
    String? imageUrl,
    bool warrantyEnabled = false,
    int? warrantyDays,
    String? warrantyCovers,
    String? warrantyExclusions,
    List<String> includedItems = const [],
    List<String> excludedItems = const [],
    List<Map<String, String>> beforeAfterPairs = const [],
  }) async {
    final row = await _client.from('vendor_service_requests').insert({
      'vendor_id': vendorId,
      'service_name': serviceName,
      if (description != null && description.isNotEmpty)
        'description': description,
      'price': price,
      'image_url': imageUrl,
      'warranty_enabled': warrantyEnabled,
      if (warrantyEnabled && warrantyDays != null) 'warranty_days': warrantyDays,
      if (warrantyEnabled && warrantyCovers != null && warrantyCovers.isNotEmpty)
        'warranty_covers': warrantyCovers,
      if (warrantyEnabled &&
          warrantyExclusions != null &&
          warrantyExclusions.isNotEmpty)
        'warranty_exclusions': warrantyExclusions,
      if (includedItems.isNotEmpty) 'included_items': includedItems,
      if (excludedItems.isNotEmpty) 'excluded_items': excludedItems,
      if (beforeAfterPairs.isNotEmpty) 'before_after_pairs': beforeAfterPairs,
    }).select('id').single();
    return row['id'] as String;
  }

  Future<void> insertServiceAttributes(
    String requestId,
    List<Map<String, dynamic>> attrs,
  ) async {
    for (final attr in attrs) {
      final attrRow = await _client
          .from('service_attributes')
          .insert({
            'custom_service_id': requestId,
            'name': attr['name'] as String,
            'field_type': 'dropdown',
            'is_required': false,
          })
          .select('id')
          .single();
      await _client.from('service_attribute_options').insert({
        'attribute_id': attrRow['id'],
        'option_name': attr['name'] as String,
        'price_adjustment': attr['price'] as double,
        'sort_order': 0,
        'discount_type': attr['discount_type'] as String,
        'discount_value': attr['discount_value'] as double,
      });
    }
  }

  Future<void> toggleCustomServiceActive(String requestId, {required bool isActive}) async {
    await _client.rpc('toggle_custom_service_active', params: {
      'p_request_id': requestId,
      'p_is_active': isActive,
    });
  }

  Future<void> deleteServiceRequest(String requestId, String vendorId) async {
    await _client.rpc('delete_vendor_service_request', params: {
      'p_request_id': requestId,
      'p_vendor_id': vendorId,
    });
  }

  Future<void> submitPriceChangeRequest({
    required String vendorId,
    required String parentRequestId,
    required String serviceName,
    required double newPrice,
  }) async {
    await _client.from('vendor_service_requests').insert({
      'vendor_id': vendorId,
      'service_name': serviceName,
      'request_type': 'price_change',
      'parent_request_id': parentRequestId,
      'new_price': newPrice,
    });
  }

  /// Marks an approved custom service as pending deletion (inline status update).
  /// No new row is created — the original new_service row's status changes.
  Future<void> requestDeletion({
    required String requestId,
    required String vendorId,
  }) async {
    await _client.rpc('vendor_request_deletion', params: {
      'p_request_id': requestId,
      'p_vendor_id': vendorId,
    });
  }
}
