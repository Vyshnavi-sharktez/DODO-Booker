import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/bot_config_repository.dart';
import '../../domain/models/bot_config.dart';

final botConfigRepositoryProvider = Provider<BotConfigRepository>((ref) {
  return BotConfigRepository(ref.watch(supabaseClientProvider));
});

class BotConfigNotifier extends StateNotifier<AsyncValue<BotConfig?>> {
  final BotConfigRepository _repo;

  BotConfigNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchConfig);
  }

  Future<void> refresh() => _load();

  Future<void> saveConfig(BotConfig config) async {
    await _repo.saveConfig(config);
    state = AsyncValue.data(config);
  }

  Future<void> setSecret(String secretName, String value) =>
      _repo.setSecret(secretName, value);

  Future<bool> secretIsSet(String secretName) =>
      _repo.secretIsSet(secretName);

  Future<String> fetchAnonKey() => _repo.fetchAnonKey();

  Future<void> saveAnonKey(String value) => _repo.saveAnonKey(value);
}

final botConfigNotifierProvider =
    StateNotifierProvider<BotConfigNotifier, AsyncValue<BotConfig?>>(
  (ref) => BotConfigNotifier(ref.watch(botConfigRepositoryProvider)),
);
