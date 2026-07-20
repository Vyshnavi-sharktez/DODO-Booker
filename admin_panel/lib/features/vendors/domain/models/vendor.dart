class Vendor {
  final String id;
  final String businessName;
  final String? ownerName;
  final String phone;
  final String email;
  final String city;
  final String? address;
  final String status;
  final bool isActive;
  final double? rating;
  final double walletBalance;
  final String? profileImageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double? latitude;
  final double? longitude;
  final double commissionRate;
  final bool isPreferredVendor;
  final double preferredVendorFee;

  const Vendor({
    required this.id,
    required this.businessName,
    this.ownerName,
    required this.phone,
    required this.email,
    required this.city,
    this.address,
    required this.status,
    required this.isActive,
    this.rating,
    this.walletBalance = 0.0,
    this.profileImageUrl,
    this.createdAt,
    this.updatedAt,
    this.latitude,
    this.longitude,
    this.commissionRate = 0.0,
    this.isPreferredVendor = false,
    this.preferredVendorFee = 0.0,
  });

  factory Vendor.fromMap(Map<String, dynamic> map) {
    return Vendor(
      id: map['id'] as String,
      businessName: map['business_name'] as String? ?? '',
      ownerName: map['owner_name'] as String?,
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      city: map['city'] as String? ?? '',
      address: map['address'] as String?,
      status: map['status'] as String? ?? 'pending',
      isActive: map['is_active'] as bool? ?? false,
      rating: (map['rating'] as num?)?.toDouble(),
      walletBalance: (map['wallet_balance'] as num?)?.toDouble() ?? 0.0,
      profileImageUrl: map['profile_image_url'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      commissionRate: (map['commission_rate'] as num?)?.toDouble() ?? 0.0,
      isPreferredVendor: (map['is_preferred_vendor'] as bool?) ?? false,
      preferredVendorFee: (map['preferred_vendor_fee'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Vendor copyWith({
    String? businessName,
    String? ownerName,
    String? phone,
    String? email,
    String? city,
    String? address,
    String? status,
    bool? isActive,
    double? rating,
    double? walletBalance,
    double? latitude,
    double? longitude,
    double? commissionRate,
    bool? isPreferredVendor,
    double? preferredVendorFee,
  }) {
    return Vendor(
      id: id,
      businessName: businessName ?? this.businessName,
      ownerName: ownerName ?? this.ownerName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      city: city ?? this.city,
      address: address ?? this.address,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      rating: rating ?? this.rating,
      walletBalance: walletBalance ?? this.walletBalance,
      createdAt: createdAt,
      updatedAt: updatedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      commissionRate: commissionRate ?? this.commissionRate,
      isPreferredVendor: isPreferredVendor ?? this.isPreferredVendor,
      preferredVendorFee: preferredVendorFee ?? this.preferredVendorFee,
    );
  }
}
