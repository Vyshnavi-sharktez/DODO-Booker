import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/vendor_service_requests_repository.dart';
import '../../domain/models/vendor_service_request.dart';

final vendorServiceRequestsRepositoryProvider =
    Provider<VendorServiceRequestsRepository>((ref) {
  return VendorServiceRequestsRepository(ref.watch(supabaseClientProvider));
});

class VendorServiceRequestsNotifier
    extends StateNotifier<AsyncValue<List<VendorServiceRequest>>> {
  VendorServiceRequestsNotifier(this._repo, this._supabase)
      : super(const AsyncValue.data([])) {
    _load();
    _subscribeRealtime();
  }

  final VendorServiceRequestsRepository _repo;
  final SupabaseClient _supabase;
  RealtimeChannel? _channel;

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('admin-vendor-service-requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vendor_service_requests',
          callback: (_) => _load(),
        )
        .subscribe();
  }

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

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _repo.toggleActive(id, isActive: isActive);
    await _load();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }
}

final vendorServiceRequestsNotifierProvider = StateNotifierProvider<
    VendorServiceRequestsNotifier,
    AsyncValue<List<VendorServiceRequest>>>((ref) {
  return VendorServiceRequestsNotifier(
    ref.watch(vendorServiceRequestsRepositoryProvider),
    ref.watch(supabaseClientProvider),
  );
});
