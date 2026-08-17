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
}
