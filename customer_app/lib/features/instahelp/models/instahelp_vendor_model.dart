import '../../vendor_catalog/models/vcs_vendor_model.dart';

class InstaHelpVendorModel {
  const InstaHelpVendorModel({
    required this.id,
    required this.businessName,
    this.rating,
    this.profileImageUrl,
    this.isOnline = false,
    this.serviceCount = 0,
    this.city,
    this.totalReviews = 0,
    this.minServicePrice,
    this.distanceKm,
    this.instantAvailable = false,
    this.scheduleAvailable = false,
    this.isVerified = false,
    this.maxDiscountPercent = 0.0,
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
  final double? distanceKm;
  final bool instantAvailable;
  final bool scheduleAvailable;
  final bool isVerified;
  final double maxDiscountPercent;

  factory InstaHelpVendorModel.fromMap(Map<String, dynamic> m) {
    return InstaHelpVendorModel(
      id: m['id'] as String,
      businessName: m['business_name'] as String? ?? '',
      rating: (m['rating'] as num?)?.toDouble(),
      profileImageUrl: m['profile_image_url'] as String?,
      isOnline: m['is_online'] as bool? ?? false,
      serviceCount: (m['service_count'] as num?)?.toInt() ?? 0,
      city: m['city'] as String?,
      totalReviews: (m['total_reviews'] as num?)?.toInt() ?? 0,
      minServicePrice: (m['min_service_price'] as num?)?.toDouble(),
      distanceKm: (m['distance_km'] as num?)?.toDouble(),
      instantAvailable: m['instant_available'] as bool? ??
          m['has_instant_mode'] as bool? ??
          false,
      scheduleAvailable: m['schedule_available'] as bool? ??
          m['has_schedule_mode'] as bool? ??
          false,
      isVerified: m['is_verified'] as bool? ?? m['is_approved'] as bool? ?? false,
      maxDiscountPercent:
          (m['max_discount_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  VcsVendorModel toVcsModel() => VcsVendorModel(
        id: id,
        businessName: businessName,
        rating: rating,
        profileImageUrl: profileImageUrl,
        isOnline: isOnline,
        serviceCount: serviceCount,
        city: city,
        totalReviews: totalReviews,
        minServicePrice: minServicePrice,
      );
}
