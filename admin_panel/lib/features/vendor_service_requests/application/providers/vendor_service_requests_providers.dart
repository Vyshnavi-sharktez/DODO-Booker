import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/vendor_service_requests_repository.dart';
import '../../domain/models/vendor_service_request.dart';

final vendorServiceRequestsRepositoryProvider =
    Provider<VendorServiceRequestsRepository>((ref) {
  return VendorServiceRequestsRepository(ref.watch(supabaseClientProvider));
});

class VendorServiceRequestsNotifier
    extends StateNotifier<AsyncValue<List<VendorServiceRequest>>> {
  VendorServiceRequestsNotifier(this._repo)
      : super(const AsyncValue.data([])) {
    _load();
  }

  final VendorServiceRequestsRepository _repo;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> refresh() => _load();

  Future<void> accept(String id) async {
    await _repo.accept(id);
    await _load();
  }

  Future<void> complete(String id) async {
    await _repo.complete(id);
    await _load();
  }

  Future<void> reject(String id, {required String reason}) async {
    await _repo.reject(id, reason: reason);
    await _load();
  }
}

final vendorServiceRequestsNotifierProvider = StateNotifierProvider<
    VendorServiceRequestsNotifier,
    AsyncValue<List<VendorServiceRequest>>>((ref) {
  return VendorServiceRequestsNotifier(
    ref.watch(vendorServiceRequestsRepositoryProvider),
  );
});
