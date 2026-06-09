class Role {
  final String id;
  final String name;
  final String? description;
  final bool isSystem;
  final bool isActive;
  final List<String> permissionIds;

  const Role({
    required this.id,
    required this.name,
    this.description,
    required this.isSystem,
    required this.isActive,
    this.permissionIds = const [],
  });

  factory Role.fromMap(Map<String, dynamic> map) {
    return Role(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      isSystem: map['is_system'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      permissionIds: (map['role_permissions'] as List<dynamic>?)
              ?.map((rp) => rp['permissions_id'] as String)
              .toList() ??
          [],
    );
  }

  Role copyWith({
    String? id,
    String? name,
    String? description,
    bool? isSystem,
    bool? isActive,
    List<String>? permissionIds,
  }) {
    return Role(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isSystem: isSystem ?? this.isSystem,
      isActive: isActive ?? this.isActive,
      permissionIds: permissionIds ?? this.permissionIds,
    );
  }

  int get permissionCount => permissionIds.length;
}
