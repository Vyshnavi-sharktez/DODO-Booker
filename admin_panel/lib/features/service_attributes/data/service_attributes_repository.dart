import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service_attribute.dart';
import '../domain/models/service_attribute_option.dart';

const _optionsSelect =
    'service_attribute_options(id, attribute_id, option_name, price_adjustment, sort_order)';

class ServiceAttributesRepository {
  final SupabaseClient _supabase;

  const ServiceAttributesRepository(this._supabase);

  Future<List<ServiceAttribute>> fetchByService(String serviceId) async {
    final data = await _supabase
        .from('service_attributes')
        .select('*, $_optionsSelect')
        .eq('service_id', serviceId)
        .order('name', ascending: true)
        .order('sort_order',
            referencedTable: 'service_attribute_options', ascending: true);
    return (data as List<dynamic>)
        .map((r) => ServiceAttribute.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceAttribute> createAttribute({
    required String serviceId,
    required String name,
    required String fieldType,
    required bool isRequired,
  }) async {
    final data = await _supabase
        .from('service_attributes')
        .insert({
          'service_id': serviceId,
          'name': name,
          'field_type': fieldType,
          'is_required': isRequired,
        })
        .select('*, $_optionsSelect')
        .single();
    return ServiceAttribute.fromMap(data);
  }

  Future<ServiceAttribute> updateAttribute(
    String id, {
    required String serviceId,
    required String name,
    required String fieldType,
    required bool isRequired,
  }) async {
    final data = await _supabase
        .from('service_attributes')
        .update({
          'service_id': serviceId,
          'name': name,
          'field_type': fieldType,
          'is_required': isRequired,
        })
        .eq('id', id)
        .select('*, $_optionsSelect')
        .single();
    return ServiceAttribute.fromMap(data);
  }

  Future<void> deleteAttribute(String id) async {
    await _supabase.from('service_attributes').delete().eq('id', id);
  }

  // ── Options ─────────────────────────────────────────────────────────────────

  Future<ServiceAttributeOption> createOption({
    required String attributeId,
    required String optionName,
    required double priceAdjustment,
    required int sortOrder,
  }) async {
    final data = await _supabase
        .from('service_attribute_options')
        .insert({
          'attribute_id': attributeId,
          'option_name': optionName,
          'price_adjustment': priceAdjustment,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return ServiceAttributeOption.fromMap(data);
  }

  Future<ServiceAttributeOption> updateOption(
    String id, {
    required String optionName,
    required double priceAdjustment,
  }) async {
    final data = await _supabase
        .from('service_attribute_options')
        .update({
          'option_name': optionName,
          'price_adjustment': priceAdjustment,
        })
        .eq('id', id)
        .select()
        .single();
    return ServiceAttributeOption.fromMap(data);
  }

  Future<void> deleteOption(String id) async {
    await _supabase.from('service_attribute_options').delete().eq('id', id);
  }

  /// Batch-updates sort_order for a reordered list of options in one request.
  Future<void> reorderOptions(
      List<({String id, int sortOrder})> updates) async {
    await _supabase.from('service_attribute_options').upsert(
          updates
              .map((u) => {'id': u.id, 'sort_order': u.sortOrder})
              .toList(),
        );
  }

  // ── Catalog node variants (Phase 2) ─────────────────────────────────────────
  // These methods query / write by node_id so they work for both migrated nodes
  // (where node_id = service_id) and brand-new catalog nodes (node_id only).

  Future<List<ServiceAttribute>> fetchByNode(String nodeId) async {
    final data = await _supabase
        .from('service_attributes')
        .select('*, $_optionsSelect')
        .eq('node_id', nodeId)
        .order('name', ascending: true)
        .order('sort_order',
            referencedTable: 'service_attribute_options', ascending: true);
    return (data as List<dynamic>)
        .map((r) => ServiceAttribute.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceAttribute> createAttributeForNode({
    required String nodeId,
    required String name,
    required String fieldType,
    required bool isRequired,
  }) async {
    final data = await _supabase
        .from('service_attributes')
        .insert({
          'node_id': nodeId,
          'name': name,
          'field_type': fieldType,
          'is_required': isRequired,
        })
        .select('*, $_optionsSelect')
        .single();
    return ServiceAttribute.fromMap(data);
  }

  Future<ServiceAttribute> updateAttributeName(
    String id, {
    required String name,
    required String fieldType,
    required bool isRequired,
  }) async {
    final data = await _supabase
        .from('service_attributes')
        .update({
          'name': name,
          'field_type': fieldType,
          'is_required': isRequired,
        })
        .eq('id', id)
        .select('*, $_optionsSelect')
        .single();
    return ServiceAttribute.fromMap(data);
  }

  /// Lightweight fetch for the service picker — returns only id + name.
  Future<List<({String id, String name})>> fetchServiceDropdowns() async {
    final data = await _supabase
        .from('services')
        .select('id, name')
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((r) => (id: r['id'] as String, name: r['name'] as String))
        .toList();
  }
}
