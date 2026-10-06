import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/push_config_repository.dart';
import '../../domain/models/push_config_status.dart';

final pushConfigRepositoryProvider = Provider<PushConfigRepository>((ref) {
  return PushConfigRepository(ref.watch(supabaseClientProvider));
});

class PushConfigNotifier
    extends StateNotifier<AsyncValue<PushConfigStatus>> {
  final PushConfigRepository _repo;

  PushConfigNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchStatus);
  }

  Future<void> refresh() => _load();

  // Stores a secret in vault. Value is never returned — see upsert_fcm_vault_secret RPC.
  Future<void> upsertFcmVaultSecret(String name, String value) =>
      _repo.upsertFcmVaultSecret(name, value);
}

final pushConfigNotifierProvider = StateNotifierProvider<PushConfigNotifier,
    AsyncValue<PushConfigStatus>>(
  (ref) => PushConfigNotifier(ref.watch(pushConfigRepositoryProvider)),
);
