class AdminUser {
  final String id;
  final String userId;
  final String fullName;
  final String email;
  final bool isSuperAdmin;
  final bool isActive;
  final Set<String> permissions;
  final List<String> roleNames;

  const AdminUser({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.isSuperAdmin,
    required this.isActive,
    required this.permissions,
    required this.roleNames,
  });

  // Super admins bypass all permission checks.
  bool hasPermission(String permission) {
    if (isSuperAdmin) return true;
    return permissions.contains(permission);
  }

  bool hasAnyPermission(List<String> perms) {
    if (isSuperAdmin) return true;
    return perms.any(permissions.contains);
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
    );
  }
}
