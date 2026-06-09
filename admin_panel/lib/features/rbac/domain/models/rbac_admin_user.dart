class RbacAdminUser {
  final String id;
  final String userId;
  final String fullName;
  final String email;
  final bool isSuperAdmin;
  final bool isActive;
  final List<String> roleIds;
  final List<String> roleNames;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;

  const RbacAdminUser({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.isSuperAdmin,
    required this.isActive,
    this.roleIds = const [],
    this.roleNames = const [],
    this.lastLoginAt,
    this.createdAt,
  });

  factory RbacAdminUser.fromMap(Map<String, dynamic> map) {
    final userRoles = map['admin_user_roles'] as List<dynamic>? ?? [];

    return RbacAdminUser(
      id: map['id'] as String,
      userId: map['auth_user_id'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      isSuperAdmin: map['is_super_admin'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      roleIds: userRoles
          .map((r) => r['role_id'] as String)
          .toList(),
      roleNames: userRoles
          .map((r) {
            final role = r['roles'] as Map<String, dynamic>?;
            return role?['name'] as String? ?? '';
          })
          .where((n) => n.isNotEmpty)
          .toList(),
      lastLoginAt: map['last_login_at'] != null
          ? DateTime.tryParse(map['last_login_at'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  String get displayName => fullName.isNotEmpty ? fullName : email;

  RbacAdminUser copyWith({
    bool? isActive,
    List<String>? roleIds,
    List<String>? roleNames,
    String? fullName,
  }) {
    return RbacAdminUser(
      id: id,
      userId: userId,
      fullName: fullName ?? this.fullName,
      email: email,
      isSuperAdmin: isSuperAdmin,
      isActive: isActive ?? this.isActive,
      roleIds: roleIds ?? this.roleIds,
      roleNames: roleNames ?? this.roleNames,
      lastLoginAt: lastLoginAt,
      createdAt: createdAt,
    );
  }
}
