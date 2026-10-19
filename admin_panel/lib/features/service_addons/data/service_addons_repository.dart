import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service_addon.dart';

const _nullSentinel = Object();

class AddonLinkedService {
  final String serviceId;
  final String serviceName;
  final String? subcategoryName;
  final String? categoryName;

  const AddonLinkedService({
    required this.serviceId,
    required this.serviceName,
    this.subcategoryName,
    this.categoryName,
  });
}

class ServiceAddonsRepository {
  final SupabaseClient _supabase;

  const ServiceAddonsRepository(this._supabase);

  Future<List<ServiceAddon>> fetchAll() async {
    final data = await _supabase
        .from('addons')
        .select()
        .order('created_at', ascending: true);
    return (data as List<dynamic>)
        .map((r) => ServiceAddon.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceAddon> create({
    required String name,
    String? description,
    required double price,
    required bool isActive,
    bool isGlobal = false,
    String? serviceId,
    String discountType = 'percentage',
    double discountValue = 0,
  }) async {
    final data = await _supabase
        .from('addons')
        .insert({
          'name': name,
          if (description != null && description.isNotEmpty)
            'description': description,
          'price': price,
          'is_active': isActive,
          'is_global': isGlobal,
          'service_id': serviceId,
          'discount_type': discountType,
          'discount_value': discountValue,
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
    bool isGlobal = false,
    Object? serviceId = _nullSentinel,
    String discountType = 'percentage',
    double discountValue = 0,
  }) async {
    final data = await _supabase
        .from('addons')
        .update({
          'name': name,
          'description': description,
          'price': price,
          'is_active': isActive,
          'is_global': isGlobal,
          'service_id': serviceId == _nullSentinel ? null : serviceId,
          'discount_type': discountType,
          'discount_value': discountValue,
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

  // ── Node-level addon assignment (catalog_node_addons junction) ───────────────

  Future<List<ServiceAddon>> fetchGlobalAddons() async {
    final data = await _supabase
        .from('addons')
        .select()
        .eq('is_global', true)
        .eq('is_active', true)
        .order('created_at', ascending: true);
    return (data as List<dynamic>)
        .map((r) => ServiceAddon.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<ServiceAddon>> fetchNodeAddons(String nodeId) async {
    final data = await _supabase
        .from('catalog_node_addons')
        .select('sort_order, addons(*)')
        .eq('node_id', nodeId)
        .order('sort_order', ascending: true);
    return (data as List).map((row) {
      final addonMap =
          Map<String, dynamic>.from(row['addons'] as Map<String, dynamic>);
      return ServiceAddon.fromMap(addonMap);
    }).toList();
  }

  Future<void> assignAddon(String nodeId, String addonId,
      {int sortOrder = 0}) async {
    await _supabase.from('catalog_node_addons').upsert({
      'node_id': nodeId,
      'addon_id': addonId,
      'sort_order': sortOrder,
    });
  }

  Future<void> unassignAddon(String nodeId, String addonId) async {
    await _supabase
        .from('catalog_node_addons')
        .delete()
        .eq('node_id', nodeId)
        .eq('addon_id', addonId);
  }

  // ── Linked services for a given addon (for the View dialog) ──────────────────
  Future<List<AddonLinkedService>> fetchAddonLinkedServices(
      String addonId) async {
    // 1. Node IDs linked to this addon
    final linkRows = await _supabase
        .from('catalog_node_addons')
        .select('node_id')
        .eq('addon_id', addonId);
    final nodeIds =
        (linkRows as List).map((r) => r['node_id'] as String).toList();
    if (nodeIds.isEmpty) return [];

    // 2. Service names
    final serviceRows = await _supabase
        .from('catalog_nodes')
        .select('id, name')
        .inFilter('id', nodeIds);
    final nodeNameById = <String, String>{
      for (final r in serviceRows as List)
        r['id'] as String: r['name'] as String? ?? '',
    };

    // 3. Subcategory parent IDs for each service
    final subRelRows = await _supabase
        .from('catalog_node_relationships')
        .select('child_id, parent_id')
        .inFilter('child_id', nodeIds);
    final subcatIdByNodeId = <String, String>{};
    final subcatIds = <String>[];
    for (final r in subRelRows as List) {
      final childId = r['child_id'] as String;
      final parentId = r['parent_id'] as String;
      subcatIdByNodeId[childId] = parentId;
      subcatIds.add(parentId);
    }

    // 4 + 5. Subcategory names and category parent IDs (parallel)
    final subcatNameById = <String, String>{};
    final catIdBySubcatId = <String, String>{};
    if (subcatIds.isNotEmpty) {
      final results = await Future.wait([
        _supabase
            .from('catalog_nodes')
            .select('id, name')
            .inFilter('id', subcatIds),
        _supabase
            .from('catalog_node_relationships')
            .select('child_id, parent_id')
            .inFilter('child_id', subcatIds),
      ]);
      for (final r in results[0] as List) {
        subcatNameById[r['id'] as String] = r['name'] as String? ?? '';
      }
      for (final r in results[1] as List) {
        catIdBySubcatId[r['child_id'] as String] = r['parent_id'] as String;
      }
    }

    // 6. Category names
    final catIds = catIdBySubcatId.values.toSet().toList();
    final catNameById = <String, String>{};
    if (catIds.isNotEmpty) {
      final catRows = await _supabase
          .from('catalog_nodes')
          .select('id, name')
          .inFilter('id', catIds);
      for (final r in catRows as List) {
        catNameById[r['id'] as String] = r['name'] as String? ?? '';
      }
    }

    return nodeIds.map((nodeId) {
      final subcatId = subcatIdByNodeId[nodeId];
      final catId = subcatId != null ? catIdBySubcatId[subcatId] : null;
      return AddonLinkedService(
        serviceId: nodeId,
        serviceName: nodeNameById[nodeId] ?? nodeId,
        subcategoryName: subcatId != null ? subcatNameById[subcatId] : null,
        categoryName: catId != null ? catNameById[catId] : null,
      );
    }).toList();
  }

}
