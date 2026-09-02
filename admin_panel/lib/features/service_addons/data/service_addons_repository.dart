import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service_addon.dart';

const _nullSentinel = Object();

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
          if (serviceId != null) 'service_id': serviceId,
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
}
