import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/customer_question.dart';

class CustomerQuestionsRepository {
  final SupabaseClient _db;

  const CustomerQuestionsRepository(this._db);

  Future<List<CustomerQuestion>> fetchForService(String serviceId) async {
    final data = await _db
        .from('customer_questions')
        .select()
        .eq('service_id', serviceId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => CustomerQuestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> answerQuestion(
    CustomerQuestion question, {
    required String serviceName,
    required String answer,
  }) async {
    await _db.from('customer_questions').update({
      'status': 'answered',
      'answer': answer,
      'answered_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', question.id);

    final preview = question.question.length > 80
        ? '${question.question.substring(0, 80)}...'
        : question.question;

    await _db.from('notifications').insert({
      'user_type': 'customer',
      'user_id': question.customerId,
      'title': 'Your question was answered',
      'message':
          'Your question about $serviceName: "$preview" has been answered.',
      'notification_type': 'question_answered',
      'is_read': false,
      'entity_type': 'service_faq',
      'entity_id': question.serviceId,
      'customer_question_id': question.id,
    });
  }

  Future<void> deleteQuestion(String id) async {
    await _db.from('customer_questions').delete().eq('id', id);
  }
}
