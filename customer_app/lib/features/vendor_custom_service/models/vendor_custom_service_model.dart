import 'package:supabase_flutter/supabase_flutter.dart';

class VendorCustomServiceModel {
  const VendorCustomServiceModel({
    required this.id,
    required this.serviceName,
    this.description,
    required this.activePrice,
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
  });

  final String id;
  final String serviceName;
  final String? description;
  final double activePrice;
  final String? imageUrl;
  final String vendorId;
  final String vendorName;
  final double rating;
  final int reviewCount;
  final List<String> includedItems;
  final List<String> excludedItems;
  final List<Map<String, String>> beforeAfterPairs;
  final bool warrantyEnabled;
  final int? warrantyDays;
  final String? warrantyCovers;
  final String? warrantyExclusions;

  String get formattedPrice => '₹${activePrice.toInt()}';

  factory VendorCustomServiceModel.fromMap(Map<String, dynamic> m) {
    return VendorCustomServiceModel(
      id: m['id'] as String,
      serviceName: m['service_name'] as String,
      description: m['description'] as String?,
      activePrice: double.parse(m['active_price'].toString()),
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
