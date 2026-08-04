import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/gps_audit_repository.dart';
import '../../domain/models/gps_cancellation_audit.dart';

final gpsAuditRepositoryProvider = Provider<GpsAuditRepository>((ref) {
  return GpsAuditRepository(ref.watch(supabaseClientProvider));
});

class GpsAuditNotifier
    extends StateNotifier<AsyncValue<List<GpsCancellationAudit>>> {
  final GpsAuditRepository _repo;

  GpsAuditNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchGpsCancellationAudits);
  }

  Future<void> refresh() => _load();

  Future<void> updateAuditStatus({
    required String auditId,
    required String newStatus,
  }) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((a) => a.id == auditId ? a.copyWith(auditStatus: newStatus) : a)
            .toList(),
      );
    }
    try {
      await _repo.updateAuditStatus(auditId: auditId, newStatus: newStatus);
    } catch (e) {
      await _load();
      rethrow;
    }
  }
}

final gpsAuditNotifierProvider = StateNotifierProvider<GpsAuditNotifier,
    AsyncValue<List<GpsCancellationAudit>>>((ref) {
  return GpsAuditNotifier(ref.watch(gpsAuditRepositoryProvider));
});
