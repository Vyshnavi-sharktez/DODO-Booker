class Customer {
  final String id;
  final String? authUserId;
  final String fullName;
  final String phone;
  final String email;
  final String? profileImageUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Customer({
    required this.id,
    this.authUserId,
    required this.fullName,
    required this.phone,
    required this.email,
    this.profileImageUrl,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String,
      authUserId: map['auth_user_id'] as String?,
      fullName: map['full_name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      profileImageUrl: map['profile_image_url'] as String?,
      isActive: map['is_active'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  Customer copyWith({
    String? fullName,
    String? phone,
    String? email,
    String? profileImageUrl,
    bool? isActive,
  }) {
    return Customer(
      id: id,
      authUserId: authUserId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
