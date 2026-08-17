import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/service_faqs_repository.dart';
import '../../domain/models/service_faq.dart';

final serviceFaqsRepositoryProvider = Provider<ServiceFaqsRepository>((ref) {
  return ServiceFaqsRepository(ref.watch(supabaseClientProvider));
});

class ServiceFaqsNotifier
    extends StateNotifier<AsyncValue<List<ServiceFaq>>> {
  final ServiceFaqsRepository _repo;
  final String _serviceId;

  ServiceFaqsNotifier(this._repo, this._serviceId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchForService(_serviceId));
  }

  Future<void> refresh() => _load();

  Future<void> create({
    required String question,
    required String answer,
  }) async {
    final current = state.valueOrNull ?? [];
    final nextOrder = current.isEmpty
        ? 0
        : current.map((f) => f.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await _repo.create(
      serviceId: _serviceId,
      question: question,
      answer: answer,
      sortOrder: nextOrder,
    );
    await _load();
  }

  Future<void> update(
    String id, {
    required String question,
    required String answer,
    required int sortOrder,
  }) async {
    await _repo.update(id,
        question: question, answer: answer, sortOrder: sortOrder);
    await _load();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await _load();
  }
}

final serviceFaqsNotifierProvider = StateNotifierProvider.family<
    ServiceFaqsNotifier, AsyncValue<List<ServiceFaq>>, String>(
  (ref, serviceId) => ServiceFaqsNotifier(
    ref.watch(serviceFaqsRepositoryProvider),
    serviceId,
  ),
);
