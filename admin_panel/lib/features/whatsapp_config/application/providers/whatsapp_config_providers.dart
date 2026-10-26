import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/whatsapp_config_repository.dart';
import '../../domain/models/whatsapp_provider_config.dart';

final whatsappConfigRepositoryProvider =
    Provider<WhatsappConfigRepository>((ref) {
  return WhatsappConfigRepository(ref.watch(supabaseClientProvider));
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class WhatsappConfigNotifier
    extends StateNotifier<AsyncValue<List<WhatsappProviderConfig>>> {
  final WhatsappConfigRepository _repo;

  WhatsappConfigNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> refresh() => _load();

  Future<void> saveConfig(WhatsappProviderConfig config) async {
    await _repo.saveConfig(config);
    final current = state.valueOrNull ?? [];
    final updated = [
      for (final c in current)
        if (c.provider == config.provider) config else c,
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

  WhatsappProviderConfig configFor(String provider) {
    return state.valueOrNull
            ?.firstWhere(
              (c) => c.provider == provider,
              orElse: () => WhatsappProviderConfig.empty(provider),
            ) ??
        WhatsappProviderConfig.empty(provider);
  }
}

final whatsappConfigNotifierProvider = StateNotifierProvider<
    WhatsappConfigNotifier,
    AsyncValue<List<WhatsappProviderConfig>>>(
  (ref) => WhatsappConfigNotifier(
    ref.watch(whatsappConfigRepositoryProvider),
  ),
);
