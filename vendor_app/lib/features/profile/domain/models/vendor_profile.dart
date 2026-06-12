class VendorProfile {
  const VendorProfile({
    required this.id,
    required this.businessName,
    required this.ownerName,
    required this.phone,
    this.email,
    this.city,
    this.address,
    this.profileImageUrl,
    this.rating = 0.0,
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String businessName;
  final String ownerName;
  final String phone;
  final String? email;
  final String? city;
  final String? address;
  final String? profileImageUrl;
  final double rating;
  final bool isActive;
  final DateTime? createdAt;

  factory VendorProfile.fromMap(Map<String, dynamic> map) {
    return VendorProfile(
      id: map['id'] as String,
      businessName: map['business_name'] as String? ?? '',
      ownerName: map['owner_name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String?,
      city: map['city'] as String?,
      address: map['address'] as String?,
      profileImageUrl: map['profile_image_url'] as String?,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  VendorProfile copyWith({
    String? businessName,
    String? ownerName,
    String? phone,
    String? email,
    String? city,
    String? address,
    String? profileImageUrl,
    bool? isActive,
  }) {
    return VendorProfile(
      id: id,
      businessName: businessName ?? this.businessName,
      ownerName: ownerName ?? this.ownerName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      city: city ?? this.city,
      address: address ?? this.address,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      rating: rating,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
