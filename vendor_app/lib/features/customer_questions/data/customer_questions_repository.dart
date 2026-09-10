import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/customer_question_model.dart';

class VendorCustomerQuestionsRepository {
  const VendorCustomerQuestionsRepository(this._db);

  final SupabaseClient _db;

  Future<List<CustomerQuestionModel>> fetchForVendor(String vendorId) async {
    try {
      // Direct table query is blocked for anon — the RLS policy only returns
      // answered rows.  Use the SECURITY DEFINER RPC so pending questions are
      // visible to the vendor.
      final data = await _db.rpc(
        'fetch_vendor_questions',
        params: {'p_vendor_id': vendorId},
      );
      return (data as List)
          .map((e) =>
              CustomerQuestionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[VendorQuestionsRepo] fetchForVendor error: $e');
      return [];
    }
  }

  Future<void> answerQuestion({
    required String questionId,
    required String vendorId,
    required String answer,
  }) async {
    await _db.rpc('answer_customer_question_as_vendor', params: {
      'p_question_id': questionId,
      'p_vendor_id': vendorId,
      'p_answer': answer,
    });
  }
}
