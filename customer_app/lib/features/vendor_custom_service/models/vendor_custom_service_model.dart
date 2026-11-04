import 'package:supabase_flutter/supabase_flutter.dart';

class VendorCustomServiceModel {
  const VendorCustomServiceModel({
    required this.id,
    required this.serviceName,
    this.description,
    required this.activePrice,
    this.basePrice,
    this.imageUrl,
    required this.vendorId,
    required this.vendorName,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.includedItems = const [],
    this.excludedItems = const [],
    this.beforeAfterPairs = const [],
    this.warrantyEnabled = false,
    this.warrantyDays,
    this.warrantyCovers,
    this.warrantyExclusions,
    this.vendorCategoryId,
    this.pricingType = 'fixed',
    this.pricePerMinute,
    this.durationMinutes,
    this.categoryName,
    this.categoryIconKey,
    this.optionsCount = 0,
    this.discountType = 'none',
    this.discountValue = 0,
  });

  final String id;
  final String serviceName;
  final String? description;
  final double activePrice;
  final double? basePrice;      // original pre-discount price (vsr.price)
  final String? imageUrl;
  final String vendorId;
  final String vendorName;
  final double rating;
  final int reviewCount;
  final int optionsCount;
  final List<String> includedItems;
  final List<String> excludedItems;
  final List<Map<String, String>> beforeAfterPairs;
  final bool warrantyEnabled;
  final int? warrantyDays;
  final String? warrantyCovers;
  final String? warrantyExclusions;
  final String? vendorCategoryId;
  final String pricingType; // 'fixed' | 'minutes_based' | 'duration_based'
  final double? pricePerMinute;
  final int? durationMinutes;
  final String? categoryName;
  final String? categoryIconKey;
  final String discountType;    // 'none' | 'percentage' | 'fixed'
  final double discountValue;

  bool get isMinutesBased => pricingType == 'minutes_based';
  bool get isDurationBased => pricingType == 'duration_based';

  bool get hasDiscount =>
      pricingType == 'fixed' &&
      discountType != 'none' &&
      discountValue > 0 &&
      basePrice != null &&
      basePrice! > activePrice;

  String get formattedPrice => '₹${activePrice.toInt()}';

  String get pricingLabel {
    if (!isMinutesBased || pricePerMinute == null || durationMinutes == null) {
      return formattedPrice;
    }
    return '₹${pricePerMinute!.toStringAsFixed(0)}/min × ${durationMinutes}min';
  }

  factory VendorCustomServiceModel.fromMap(Map<String, dynamic> m) {
    return VendorCustomServiceModel(
      id: m['id'] as String,
      serviceName: m['service_name'] as String,
      description: m['description'] as String?,
      activePrice: double.parse(m['active_price'].toString()),
      basePrice: m['price'] != null
          ? double.tryParse(m['price'].toString())
          : null,
      imageUrl: m['image_url'] as String?,
      vendorId: m['vendor_id'] as String,
      vendorName: m['vendor_name'] as String,
      rating: m['rating'] != null
          ? double.parse(m['rating'].toString())
          : 0.0,
      reviewCount: (m['review_count'] as int?) ?? 0,
      includedItems: (m['included_items'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      excludedItems: (m['excluded_items'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      beforeAfterPairs: (m['before_after_pairs'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(
                  (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
              .toList() ??
          [],
      warrantyEnabled: (m['warranty_enabled'] as bool?) ?? false,
      warrantyDays: m['warranty_days'] as int?,
      warrantyCovers: m['warranty_covers'] as String?,
      warrantyExclusions: m['warranty_exclusions'] as String?,
      vendorCategoryId: m['vendor_category_id'] as String?,
      pricingType: m['pricing_type'] as String? ?? 'fixed',
      pricePerMinute: (m['price_per_minute'] as num?)?.toDouble(),
      durationMinutes: (m['duration_minutes'] as num?)?.toInt(),
      categoryName: m['category_name'] as String?,
      categoryIconKey: m['category_icon_key'] as String?,
      optionsCount: (m['options_count'] as num?)?.toInt() ?? 0,
      discountType: m['discount_type'] as String? ?? 'none',
      discountValue: (m['discount_value'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Searches active vendor custom services by name/description.
  /// Returns DODO catalog results separately — caller concatenates.
  static Future<List<VendorCustomServiceModel>> search(String query) async {
    try {
      final data = await Supabase.instance.client
          .rpc('search_vendor_custom_services', params: {'p_query': query});
      return (data as List)
          .map((e) => VendorCustomServiceModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
