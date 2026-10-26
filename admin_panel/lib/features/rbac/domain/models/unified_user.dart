import 'rbac_admin_user.dart';
import '../../../vendors/domain/models/vendor.dart';

enum UnifiedUserType { admin, vendor }

class UnifiedUser {
  final UnifiedUserType type;
  final String id;
  final String displayName;
  final String phone;
  final String email;
  final bool isActive;
  final DateTime? joinedAt;
  final RbacAdminUser? admin;
  final Vendor? vendor;

  const UnifiedUser({
    required this.type,
    required this.id,
    required this.displayName,
    required this.phone,
    required this.email,
    required this.isActive,
    this.joinedAt,
    this.admin,
    this.vendor,
  });

  factory UnifiedUser.fromAdmin(RbacAdminUser a) => UnifiedUser(
        type: UnifiedUserType.admin,
        id: a.id,
        displayName: a.displayName,
        phone: a.phone ?? '',
        email: a.email,
        isActive: a.isActive,
        joinedAt: a.createdAt,
        admin: a,
      );

  factory UnifiedUser.fromVendor(Vendor v) => UnifiedUser(
        type: UnifiedUserType.vendor,
        id: v.id,
        displayName: v.ownerName?.isNotEmpty == true ? v.ownerName! : v.businessName,
        phone: v.phone,
        email: v.email,
        isActive: v.isActive,
        joinedAt: v.createdAt,
        vendor: v,
      );
}
