class AdminUser {
  final String id;
  final String userId;
  final String fullName;
  final String email;
  final bool isSuperAdmin;
  final bool isActive;
  final Set<String> permissions;
  final List<String> roleNames;
  final String? adminNumber;

  const AdminUser({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.isSuperAdmin,
    required this.isActive,
    required this.permissions,
    required this.roleNames,
    this.adminNumber,
  });

  // Backward-compat map: old coarse permission keys → granular CRUD keys they imply.
  // Roles that still carry coarse permissions (e.g. booking.view) continue to pass
  // hasPermission checks for the equivalent CRUD keys without requiring a role edit.
  static const Map<String, List<String>> legacyImplied = {
    'booking.view': [
      'booking.create', 'booking.read', 'booking.update', 'booking.delete',
    ],
    'customer.view': [
      'customer.create', 'customer.read', 'customer.update', 'customer.delete',
    ],
    'vendor.view': [
      'vendor.create', 'vendor.read', 'vendor.update', 'vendor.delete',
    ],
    'category.view': [
      'catalog.create', 'catalog.read', 'catalog.update', 'catalog.delete',
    ],
    'service.view': [
      'catalog.create', 'catalog.read', 'catalog.update', 'catalog.delete',
    ],
    'coupon.view': [
      'coupon.create', 'coupon.read', 'coupon.update', 'coupon.delete',
    ],
    'dodo_team.view': [
      'dodo_team.create', 'dodo_team.read', 'dodo_team.update', 'dodo_team.delete',
    ],
    'settings.manage': [
      'settings.read', 'settings.update',
      'scheduling.create', 'scheduling.read', 'scheduling.update', 'scheduling.delete',
      'notification.create', 'notification.read',
      'support.read', 'support.update',
    ],
    'rbac.manage': [
      'rbac.create', 'rbac.read', 'rbac.update', 'rbac.delete',
    ],
    'refund.view': ['refund.read'],
  };

  // Super admins bypass all permission checks.
  // Also checks legacy coarse permissions that imply the requested granular key.
  bool hasPermission(String permission) {
    if (isSuperAdmin) return true;
    if (permissions.contains(permission)) return true;
    for (final held in permissions) {
      final implied = legacyImplied[held];
      if (implied != null && implied.contains(permission)) return true;
    }
    return false;
  }

  bool hasAnyPermission(List<String> perms) {
    if (isSuperAdmin) return true;
    return perms.any(hasPermission);
  }

  String get displayName => fullName.isNotEmpty ? fullName : email;

  String get primaryRole {
    if (isSuperAdmin) return 'Super Admin';
    return roleNames.isNotEmpty ? roleNames.first : 'Admin';
  }

  AdminUser copyWith({
    String? id,
    String? userId,
    String? fullName,
    String? email,
    bool? isSuperAdmin,
    bool? isActive,
    Set<String>? permissions,
    List<String>? roleNames,
    String? adminNumber,
  }) {
    return AdminUser(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      isActive: isActive ?? this.isActive,
      permissions: permissions ?? this.permissions,
      roleNames: roleNames ?? this.roleNames,
      adminNumber: adminNumber ?? this.adminNumber,
    );
  }
}
