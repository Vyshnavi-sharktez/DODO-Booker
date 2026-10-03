import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service_faq.dart';

class ServiceFaqsRepository {
  final SupabaseClient _supabase;
  const ServiceFaqsRepository(this._supabase);

  Future<List<ServiceFaq>> fetchForService(String serviceId) async {
    final data = await _supabase
        .from('service_faqs')
        .select()
        .eq('service_id', serviceId)
        .order('sort_order', ascending: true);
    return (data as List)
        .map((r) => ServiceFaq.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<ServiceFaq>> fetchForCustomService(String customServiceId) async {
    final data = await _supabase
        .from('service_faqs')
        .select()
        .eq('custom_service_id', customServiceId)
        .order('sort_order', ascending: true);
    return (data as List)
        .map((r) => ServiceFaq.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceFaq> create({
    required String serviceId,
    required String question,
    required String answer,
    required int sortOrder,
  }) async {
    final data = await _supabase
        .from('service_faqs')
        .insert({
          'service_id': serviceId,
          'question': question,
          'answer': answer,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return ServiceFaq.fromMap(data);
  }

  Future<ServiceFaq> createForCustomService({
    required String customServiceId,
    required String question,
    required String answer,
    required int sortOrder,
  }) async {
    final data = await _supabase
        .from('service_faqs')
        .insert({
          'custom_service_id': customServiceId,
          'question': question,
          'answer': answer,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return ServiceFaq.fromMap(data);
  }

  Future<ServiceFaq> update(
    String id, {
    required String question,
    required String answer,
    required int sortOrder,
  }) async {
    final data = await _supabase
        .from('service_faqs')
        .update({
          'question': question,
          'answer': answer,
          'sort_order': sortOrder,
        })
        .eq('id', id)
        .select()
        .single();
    return ServiceFaq.fromMap(data);
  }

  Future<void> delete(String id) async {
    await _supabase.from('service_faqs').delete().eq('id', id);
  }

  /// Swaps sort_order with the adjacent FAQ in the given direction.
  Future<void> moveFaq(String id, String direction) async {
    await _supabase.rpc('move_service_faq', params: {
      'p_faq_id': id,
      'p_direction': direction,
    });
  }

  /// Closes gaps in sort_order after a deletion.
  Future<void> normalizeSortOrders({
    String? serviceId,
    String? customServiceId,
  }) async {
    await _supabase.rpc('normalize_service_faq_sort_orders', params: {
      'p_service_id': serviceId,
      'p_custom_service_id': customServiceId,
    });
  }
}
