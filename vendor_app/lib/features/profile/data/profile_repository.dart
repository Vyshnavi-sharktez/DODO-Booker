import '../../../shared/repositories/base_repository.dart';
import '../domain/models/vendor_profile.dart';

class ProfileRepository extends BaseRepository {
  const ProfileRepository(super.supabase);

  Future<VendorProfile> fetchProfile(String vendorId) async =>
      throw UnimplementedError();

  Future<VendorProfile> updateProfile(
    String vendorId,
    Map<String, dynamic> fields,
  ) async =>
      throw UnimplementedError();
}
