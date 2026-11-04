class VcsVendorModel {
  const VcsVendorModel({
    required this.id,
    required this.businessName,
    this.rating,
    this.profileImageUrl,
    this.isOnline = false,
    this.serviceCount = 0,
    this.city,
    this.totalReviews = 0,
    this.minServicePrice,
  });

  final String id;
  final String businessName;
  final double? rating;
  final String? profileImageUrl;
  final bool isOnline;
  final int serviceCount;
  final String? city;
  final int totalReviews;
  final double? minServicePrice;

  factory VcsVendorModel.fromMap(Map<String, dynamic> m) {
    return VcsVendorModel(
      id: m['id'] as String,
      businessName: m['business_name'] as String? ?? '',
      rating: (m['rating'] as num?)?.toDouble(),
      profileImageUrl: m['profile_image_url'] as String?,
      isOnline: m['is_online'] as bool? ?? false,
      serviceCount: (m['service_count'] as num?)?.toInt() ?? 0,
      city: m['city'] as String?,
      totalReviews: (m['total_reviews'] as num?)?.toInt() ?? 0,
      minServicePrice: (m['min_service_price'] as num?)?.toDouble(),
    );
  }
}
