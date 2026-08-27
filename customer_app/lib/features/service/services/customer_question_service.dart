import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer_question_model.dart';

class CustomerQuestionService {
  final _db = Supabase.instance.client;

  Future<List<CustomerQuestionModel>> fetchAnsweredForService(
      String serviceId) async {
    final data = await _db
        .from('customer_questions')
        .select()
        .eq('service_id', serviceId)
        .eq('status', 'answered')
        .order('created_at', ascending: true);
    return (data as List)
        .map((e) => CustomerQuestionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> submitQuestion({
    required String serviceId,
    required String serviceName,
    required String customerId,
    required String? customerName,
    required String? customerPhone,
    required String question,
  }) async {
    final row = await _db.from('customer_questions').insert({
      'service_id': serviceId,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'question': question,
      'status': 'pending',
    }).select('id').single();
    final questionId = row['id'] as String;

    final preview =
        question.length > 80 ? '${question.substring(0, 80)}...' : question;

    await _db.from('notifications').insert({
      'user_type': 'admin',
      'title': 'New Customer Question',
      'message':
          '${customerName ?? 'A customer'} asked about $serviceName: "$preview"',
      'notification_type': 'customer_question',
      'is_read': false,
      'entity_type': 'customer_question',
      'entity_id': serviceId,
      'customer_question_id': questionId,
    });
  }
}
