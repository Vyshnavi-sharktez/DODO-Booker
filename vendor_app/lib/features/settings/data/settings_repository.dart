import '../../../shared/repositories/base_repository.dart';
import '../domain/models/vendor_settings.dart';

class SettingsRepository extends BaseRepository {
  const SettingsRepository(super.supabase);

  Future<VendorSettings> fetchSettings(String vendorId) async =>
      throw UnimplementedError();

  Future<void> updateSettings(
    String vendorId,
    VendorSettings settings,
  ) async {}
}
