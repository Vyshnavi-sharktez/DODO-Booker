import '../models/vendor_profile.dart';

abstract interface class IProfileRepository {
  Future<VendorProfile?> getProfileByPhone(String phone);
  Future<void> updateProfileByPhone({
    required String phone,
    required Map<String, dynamic> fields,
  });
}
