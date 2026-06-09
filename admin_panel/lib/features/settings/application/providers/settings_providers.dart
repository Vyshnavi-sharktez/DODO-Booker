import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/settings_defaults.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(supabaseClientProvider));
});

class SettingsNotifier
    extends StateNotifier<AsyncValue<Map<String, String>>> {
  final SettingsRepository _repo;

  SettingsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> refresh() => _load();

  // Returns the effective value for a key: DB value if present, else default.
  static String effectiveValue(Map<String, String> settings, String key) =>
      settings[key] ?? kSettingDefaults[key] ?? '';

  // Upserts a section's key-value pairs and patches local state immediately.
  Future<void> saveSection(Map<String, String> keyValues) async {
    await _repo.upsertMany(keyValues);
    final current = state.valueOrNull ?? {};
    state = AsyncValue.data({...current, ...keyValues});
  }
}

final settingsNotifierProvider = StateNotifierProvider<SettingsNotifier,
    AsyncValue<Map<String, String>>>(
  (ref) => SettingsNotifier(ref.watch(settingsRepositoryProvider)),
);
