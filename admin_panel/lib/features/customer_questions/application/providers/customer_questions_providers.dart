import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/customer_questions_repository.dart';
import '../../domain/models/customer_question.dart';

final customerQuestionsRepositoryProvider =
    Provider<CustomerQuestionsRepository>((ref) {
  return CustomerQuestionsRepository(ref.watch(supabaseClientProvider));
});

class CustomerQuestionsNotifier
    extends StateNotifier<AsyncValue<List<CustomerQuestion>>> {
  final CustomerQuestionsRepository _repo;
  final String _serviceId;
  final String _serviceName;
  final String? _parentNodeId;

  CustomerQuestionsNotifier(
      this._repo, this._serviceId, this._serviceName, this._parentNodeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.fetchForService(_serviceId, parentNodeId: _parentNodeId),
    );
  }

  Future<void> refresh() => _load();

  Future<void> answerQuestion(CustomerQuestion question,
      {required String answer}) async {
    await _repo.answerQuestion(
      question,
      serviceName: _serviceName,
      answer: answer,
    );
    await _load();
  }

  Future<void> deleteQuestion(String id) async {
    await _repo.deleteQuestion(id);
    await _load();
  }
}

typedef _Key = ({String serviceId, String serviceName, String? parentNodeId});

final customerQuestionsNotifierProvider = StateNotifierProvider.family<
    CustomerQuestionsNotifier, AsyncValue<List<CustomerQuestion>>, _Key>(
  (ref, key) => CustomerQuestionsNotifier(
    ref.watch(customerQuestionsRepositoryProvider),
    key.serviceId,
    key.serviceName,
    key.parentNodeId,
  ),
);
