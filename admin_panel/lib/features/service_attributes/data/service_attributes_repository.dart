import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service_attribute.dart';
import '../domain/models/service_attribute_option.dart';

const _optionsSelect =
    'service_attribute_options(id, attribute_id, option_name, price_adjustment)';

class ServiceAttributesRepository {
  final SupabaseClient _supabase;

  const ServiceAttributesRepository(this._supabase);

  Future<List<ServiceAttribute>> fetchByService(String serviceId) async {
    final data = await _supabase
        .from('service_attributes')
        .select('*, $_optionsSelect')
        .eq('service_id', serviceId)
        .order('name', ascending: true);
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
  }) async {
    final data = await _supabase
        .from('service_attribute_options')
        .insert({
          'attribute_id': attributeId,
          'option_name': optionName,
          'price_adjustment': priceAdjustment,
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
}
