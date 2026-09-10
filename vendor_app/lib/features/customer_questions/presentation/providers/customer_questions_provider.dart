import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/customer_questions_repository.dart';
import '../../domain/models/customer_question_model.dart';

final vendorCustomerQuestionsRepositoryProvider =
    Provider<VendorCustomerQuestionsRepository>(
  (_) => VendorCustomerQuestionsRepository(Supabase.instance.client),
);

class VendorQuestionsNotifier
    extends StateNotifier<AsyncValue<List<CustomerQuestionModel>>> {
  VendorQuestionsNotifier(this._repo, this._vendorId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final VendorCustomerQuestionsRepository _repo;
  final String _vendorId;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.fetchForVendor(_vendorId),
    );
  }

  Future<void> refresh() => _load();

  Future<void> answerQuestion({
    required String questionId,
    required String answer,
  }) async {
    await _repo.answerQuestion(
      questionId: questionId,
      vendorId: _vendorId,
      answer: answer,
    );
    await _load();
  }
}

final vendorQuestionsNotifierProvider = StateNotifierProvider.family<
    VendorQuestionsNotifier,
    AsyncValue<List<CustomerQuestionModel>>,
    String>(
  (ref, vendorId) => VendorQuestionsNotifier(
    ref.watch(vendorCustomerQuestionsRepositoryProvider),
    vendorId,
  ),
);
