import 'dart:typed_data';
import '../models/vendor_profile.dart';

abstract interface class IProfileRepository {
  Future<VendorProfile?> getProfileByPhone(String phone);
  Future<void> updateProfileByPhone({
    required String phone,
    required Map<String, dynamic> fields,
  });
  Future<String> uploadProfilePhoto({
    required String vendorId,
    required Uint8List bytes,
    required String contentType,
  });
}
