class VendorProfile {
  const VendorProfile({
    required this.id,
    required this.businessName,
    this.ownerName,
    required this.phone,
    this.email,
    this.address,
    this.city,
    required this.status,
    required this.isActive,
    this.rating,
    required this.walletBalance,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String businessName;
  final String? ownerName;
  final String phone;
  final String? email;
  final String? address;
  final String? city;
  final String status;
  final bool isActive;
  final double? rating;
  final double walletBalance;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory VendorProfile.fromMap(Map<String, dynamic> map) {
    return VendorProfile(
      id: map['id'] as String,
      businessName: map['business_name'] as String? ?? '',
      ownerName: map['owner_name'] as String?,
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String?,
      address: map['address'] as String?,
      city: map['city'] as String?,
      status: map['status'] as String? ?? 'active',
      isActive: map['is_active'] as bool? ?? true,
      rating: (map['rating'] as num?)?.toDouble(),
      walletBalance: (map['wallet_balance'] as num?)?.toDouble() ?? 0.0,
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
