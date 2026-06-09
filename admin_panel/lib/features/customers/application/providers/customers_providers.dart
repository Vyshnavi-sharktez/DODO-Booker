import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/customers_repository.dart';
import '../../domain/models/customer.dart';

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  return CustomersRepository(ref.watch(supabaseClientProvider));
});

class CustomersNotifier extends StateNotifier<AsyncValue<List<Customer>>> {
  final CustomersRepository _repo;

  CustomersNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchCustomers);
  }

  Future<void> refresh() => _load();

  Future<void> updateCustomer(
    String id, {
    required String fullName,
    required String phone,
    required String email,
    String? profileImageUrl,
    required bool isActive,
  }) async {
    final updated = await _repo.updateCustomer(
      id,
      fullName: fullName,
      phone: phone,
      email: email,
      profileImageUrl: profileImageUrl,
      isActive: isActive,
    );
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((c) => c.id == id ? updated : c).toList(),
      );
    }
  }

  Future<void> toggleActive(String id, {required bool currentIsActive}) async {
    final newIsActive = !currentIsActive;
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((c) => c.id == id ? c.copyWith(isActive: newIsActive) : c)
            .toList(),
      );
    }
    try {
      await _repo.updateActive(id, isActive: newIsActive);
    } catch (e) {
      await _load();
      rethrow;
    }
  }
}

final customersNotifierProvider =
    StateNotifierProvider<CustomersNotifier, AsyncValue<List<Customer>>>((ref) {
  return CustomersNotifier(ref.watch(customersRepositoryProvider));
});
