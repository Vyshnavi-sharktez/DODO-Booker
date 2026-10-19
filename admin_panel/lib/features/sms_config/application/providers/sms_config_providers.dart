import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/sms_config_repository.dart';
import '../../domain/models/sms_provider_config.dart';

final smsConfigRepositoryProvider = Provider<SmsConfigRepository>((ref) {
  return SmsConfigRepository(ref.watch(supabaseClientProvider));
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class SmsConfigNotifier
    extends StateNotifier<AsyncValue<List<SmsProviderConfig>>> {
  final SmsConfigRepository _repo;

  SmsConfigNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> refresh() => _load();

  Future<void> saveConfig(SmsProviderConfig config) async {
    await _repo.saveConfig(config);
    final current = state.valueOrNull ?? [];
    final updated = [
      for (final c in current)
        if (c.provider == config.provider)
          config
        else if (config.isEnabled)
          // Mirror the DB single-active-provider trigger so the UI reflects the
          // constraint immediately without requiring a manual refresh.
          c.copyWith(isEnabled: false)
        else
          c,
    ];
    if (!updated.any((c) => c.provider == config.provider)) {
      updated.add(config);
    }
    state = AsyncValue.data(updated);
  }

  Future<void> setSecret(
    String provider,
    String secretName,
    String value,
  ) =>
      _repo.setSecret(provider, secretName, value);

  Future<bool> secretIsSet(String provider, String secretName) =>
      _repo.secretIsSet(provider, secretName);

  Future<Map<String, dynamic>> sendTestMessage(
    String provider,
    String testPhone,
  ) =>
      _repo.sendTestMessage(provider, testPhone);

  SmsProviderConfig configFor(String provider) {
    return state.valueOrNull
            ?.firstWhere(
              (c) => c.provider == provider,
              orElse: () => SmsProviderConfig.empty(provider),
            ) ??
        SmsProviderConfig.empty(provider);
  }
}

final smsConfigNotifierProvider =
    StateNotifierProvider<SmsConfigNotifier, AsyncValue<List<SmsProviderConfig>>>(
  (ref) => SmsConfigNotifier(ref.watch(smsConfigRepositoryProvider)),
);
