import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/settings_repository.dart';
import '../../domain/models/vendor_settings.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseClientProvider)),
);

class SettingsNotifier extends StateNotifier<VendorSettings> {
  SettingsNotifier(SettingsRepository _) : super(const VendorSettings());

  Future<void> load(String vendorId) async {}

  Future<void> update(String vendorId, VendorSettings settings) async {
    state = settings;
  }
}

final settingsNotifierProvider =
    StateNotifierProvider<SettingsNotifier, VendorSettings>(
  (ref) => SettingsNotifier(ref.watch(settingsRepositoryProvider)),
);
