import '../../domain/entities/vendor_user.dart';

class VendorUserModel extends VendorUser {
  const VendorUserModel({
    required super.id,
    required super.phone,
    super.name,
    super.email,
    super.avatarUrl,
    required super.isActive,
  });

  /// Maps a row from the [vendors] table to a [VendorUser] entity.
  factory VendorUserModel.fromVendorRow({
    required Map<String, dynamic> row,
    required String phone,
  }) {
    return VendorUserModel(
      id: row['id'] as String,
      phone: phone,
      name: row['business_name'] as String?,
      email: row['email'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      isActive: row['is_active'] as bool? ?? true,
    );
  }

  /// Fallback when the phone is authenticated but has no [vendors] row yet.
  factory VendorUserModel.fromPhone(String phone) {
    return VendorUserModel(
      id: phone,
      phone: phone,
      isActive: true,
    );
  }
}
