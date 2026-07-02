import '../../domain/entities/vendor_user.dart';

class VendorUserModel extends VendorUser {
  const VendorUserModel({
    required super.id,
    required super.phone,
    super.name,
    super.email,
    super.avatarUrl,
    required super.isActive,
    super.userType = 'vendor',
    super.dodoTeamId,
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
      userType: 'vendor',
    );
  }

  /// Maps a row from the [dodo_teams] table to a [VendorUser] entity.
  factory VendorUserModel.fromDodoTeamRow({
    required Map<String, dynamic> row,
    required String phone,
  }) {
    final teamId = row['id'] as String;
    return VendorUserModel(
      id: teamId,
      phone: phone,
      name: row['team_name'] as String?,
      isActive: row['is_active'] as bool? ?? true,
      userType: 'dodo_team',
      dodoTeamId: teamId,
    );
  }

  /// Fallback when the phone is authenticated but has no [vendors] row yet.
  factory VendorUserModel.fromPhone(String phone) {
    return VendorUserModel(
      id: phone,
      phone: phone,
      isActive: true,
      userType: 'vendor',
    );
  }
}
